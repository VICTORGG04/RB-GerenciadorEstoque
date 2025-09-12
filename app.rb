# -*- coding: utf-8 -*-
require 'sinatra'
require 'sqlite3'
require 'bcrypt'
require 'securerandom'
require 'date'
require 'json'
require 'nokogiri'
require 'csv'
require 'roo'

# --- Configuração ---
enable :sessions
# CORREÇÃO DE MESTRE: A chave de sessão deve ser fixa para manter o login após reiniciar o servidor
set :session_secret, 'UmaChaveSecretaMuitoMaisDoQueSessentaEQuatroCaracteresParaOCodigoDoMestre'
set :bind, '0.0.0.0'
set :port, 4567

DB_PATH = File.join(File.dirname(__FILE__), "estoque.db")
DB_CONN = SQLite3::Database.new(DB_PATH)
DB_CONN.results_as_hash = true

def setup_database
  DB_CONN.execute <<-SQL
    CREATE TABLE IF NOT EXISTS produtos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT,
      quantidade INTEGER,
      preco REAL,
      categoria TEXT,
      codigo TEXT,
      data_adicionado TEXT
    );
  SQL
  DB_CONN.execute <<-SQL
    CREATE TABLE IF NOT EXISTS usuarios (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE,
      password TEXT
    );
  SQL
  if DB_CONN.execute("SELECT COUNT(*) FROM usuarios WHERE username = 'admin'").first[0] == 0
    password_hash = BCrypt::Password.create('admin123')
    DB_CONN.execute("INSERT INTO usuarios (username, password) VALUES (?, ?)", ['admin', password_hash])
    puts "============================================="
    puts "Usuário 'admin' criado com sucesso! (senha: admin123)"
    puts "============================================="
  end
  DB_CONN.execute <<-SQL
    CREATE TABLE IF NOT EXISTS relatorios_semestrais (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      data_inicio TEXT,
      data_fim TEXT,
      valor_total REAL
    );
  SQL
  DB_CONN.execute <<-SQL
    CREATE TABLE IF NOT EXISTS movimentacoes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      produto_id INTEGER,
      nome_produto TEXT,
      tipo_movimentacao TEXT,
      detalhes TEXT,
      data_movimentacao TEXT
    );
  SQL
end

setup_database

# --- Helpers ---
helpers do
  def db
    DB_CONN
  end
  def logged_in?
    !!session[:usuario_id]
  end
  def redirect_unless_logged_in
    redirect '/login' unless logged_in?
  end
  def h(text)
    Rack::Utils.escape_html(text.to_s)
  end
  def registra_movimentacao(tipo, produto = {}, detalhes = '')
    db.execute("INSERT INTO movimentacoes (produto_id, nome_produto, tipo_movimentacao, detalhes, data_movimentacao) VALUES (?, ?, ?, ?, ?)",
               [produto && produto['id'], produto && produto['nome'], tipo, detalhes, DateTime.now.to_s])
  end
  def importar_nfe(tempfile)
    doc = Nokogiri::XML(File.open(tempfile))
    ns = { nfe: 'http://www.portalfiscal.inf.br/nfe' }
    doc.xpath('//nfe:det', ns).each do |p|
      nome = p.xpath('.//nfe:xProd', ns).text
      qtd = p.xpath('.//nfe:qCom', ns).text.to_i
      preco = p.xpath('.//nfe:vUnCom', ns).text.to_f
      codigo = p.xpath('.//nfe:cProd', ns).text
      db.execute("INSERT INTO produtos (nome, quantidade, preco, categoria, codigo, data_adicionado) VALUES (?, ?, ?, ?, ?, ?)",
                 [nome, qtd, preco, 'Importado NF-e', codigo, Date.today.to_s])
    end
  end
  def importar_csv(tempfile)
    CSV.foreach(tempfile.path, headers: true, col_sep: ';') do |row|
      nome = row[0]
      qtd = (row[1] || 0).to_i
      preco = (row[2] || 0).to_f
      categoria = row[3]
      codigo = row[4]
      db.execute("INSERT INTO produtos (nome, quantidade, preco, categoria, codigo, data_adicionado) VALUES (?, ?, ?, ?, ?, ?)",
                 [nome, qtd, preco, categoria, codigo, Date.today.to_s])
    end
  end
  def importar_excel(tempfile)
    excel = Roo::Spreadsheet.open(tempfile.path)
    sheet = excel.sheet(0)
    sheet.each_with_index do |row, idx|
      next if idx == 0
      next if row.compact.empty?
      nome = row[0].to_s
      qtd = (row[1] || 0).to_i
      preco = (row[2] || 0).to_f
      categoria = row[3].to_s
      codigo = row[4].to_s
      db.execute("INSERT INTO produtos (nome, quantidade, preco, categoria, codigo, data_adicionado) VALUES (?, ?, ?, ?, ?, ?)", [nome, qtd, preco, categoria, codigo, Date.today.to_s])
    end
  end
end

get '/' do
  redirect_unless_logged_in
  @sucesso = params[:sucesso]
  @erro = params[:erro]

  @valor_total = db.get_first_value("SELECT SUM(preco * quantidade) FROM produtos") || 0
  @quantidade_total = db.get_first_value("SELECT SUM(quantidade) FROM produtos") || 0
  @valor_por_categoria = db.execute("SELECT categoria, SUM(preco * quantidade) as total FROM produtos GROUP BY categoria")

  mes_ano_atual = Date.today.strftime('%Y-%m')
  @produtos = db.execute("SELECT * FROM produtos WHERE strftime('%Y-%m', data_adicionado) = ?", [mes_ano_atual])

  erb :index
end

get('/login'){ @body_class = 'pagina-login'; erb :login }
post '/login' do
  usuario = db.get_first_row("SELECT * FROM usuarios WHERE username = ?", [params[:username]])
  if usuario && BCrypt::Password.new(usuario['password']) == params[:password]
    session[:usuario_id] = usuario['id']
    session[:username] = usuario['username']
    redirect '/'
  else
    redirect '/login?erro=1'
  end
end
get('/logout'){ session.clear; redirect '/login' }

get '/importar' do
  redirect_unless_logged_in
  @body_class = 'pagina-formulario-fundo'
  erb :importar
end
post '/importar' do
  redirect_unless_logged_in
  unless params[:arquivo] && params[:arquivo][:tempfile]
    redirect '/?erro=Nenhum arquivo selecionado'
  end
  tempfile = params[:arquivo][:tempfile]
  filename = params[:arquivo][:filename]
  begin
    case File.extname(filename).downcase
    when '.xml'
      importar_nfe(tempfile.path)
    when '.csv'
      importar_csv(tempfile)
    when '.xlsx', '.xls'
      importar_excel(tempfile)
    else
      return redirect '/?erro=Formato de arquivo não suportado'
    end
    redirect '/?sucesso=Arquivo importado com sucesso!'
  rescue => e
    puts "ERRO AO IMPORTAR: #{e.class} - #{e.message}"
    redirect "/?erro=Falha ao processar o arquivo. Verifique o formato e as colunas."
  end
end

get('/produtos/novo'){ redirect_unless_logged_in; @body_class = 'pagina-formulario-fundo'; erb :novo_produto }
post '/produtos/novo' do
  redirect_unless_logged_in
  db.execute("INSERT INTO produtos (nome, quantidade, preco, categoria, codigo, data_adicionado) VALUES (?, ?, ?, ?, ?, ?)",
             [params[:nome], params[:quantidade].to_i, params[:preco].to_f, params[:categoria], params[:codigo], Date.today.to_s])
  produto = db.get_first_row("SELECT * FROM produtos WHERE id = last_insert_rowid()")
  registra_movimentacao('criacao', produto, "Produto criado via painel")
  redirect '/'
end

get '/produtos/:id/editar' do
  redirect_unless_logged_in
  @body_class = 'pagina-formulario-fundo'
  @produto = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [params[:id]])
  redirect '/' unless @produto
  erb :editar_produto
end
post '/produtos/:id/editar' do
  redirect_unless_logged_in
  produto_antigo = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [params[:id]])
  db.execute("UPDATE produtos SET nome=?, quantidade=?, preco=?, categoria=?, codigo=? WHERE id=?",
             [params[:nome], params[:quantidade].to_i, params[:preco].to_f, params[:categoria], params[:codigo], params[:id]])
  produto_novo = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [params[:id]])
  registra_movimentacao('atualizacao', produto_novo, "Atualizado: #{produto_antigo['nome']} -> #{produto_novo['nome']}")
  redirect '/'
end
post '/produtos/excluir' do
  redirect_unless_logged_in
  ids = params[:produtos_ids] || []
  ids = [ids] unless ids.is_a?(Array)
  ids.map!(&:to_i)
  ids.each do |id|
    produto = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [id])
    if produto
      db.execute("DELETE FROM produtos WHERE id = ?", [id])
      registra_movimentacao('exclusao', produto, "Produto excluído manualmente")
    end
  end
  redirect '/'
end

get '/relatorios' do
  redirect_unless_logged_in
  @produtos = db.execute("SELECT * FROM produtos ORDER BY categoria, nome ASC")
  @total_produtos = @produtos.length
  erb :relatorios
end
get('/historico'){ redirect_unless_logged_in; @historico = db.execute("SELECT * FROM relatorios_semestrais ORDER BY data_inicio DESC"); erb :historico }
get '/movimentacoes' do
  redirect_unless_logged_in
  @mov = db.execute("SELECT * FROM movimentacoes ORDER BY data_movimentacao DESC LIMIT 200")
  erb :movimentacoes
end