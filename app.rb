# -*- coding: utf-8 -*-
require 'sinatra'
require 'sqlite3'
require 'bcrypt'
require 'securerandom'
require 'date'
require 'json'
require 'csv'
require 'roo'

# --- Configuração ---
enable :sessions
set :session_secret, SecureRandom.hex(64)
set :bind, '0.0.0.0'
set :port, 4567

DB_PATH = File.join(File.dirname(__FILE__), "estoque.db")
DB_CONN = SQLite3::Database.new(DB_PATH)
DB_CONN.results_as_hash = true

def setup_database
  DB_CONN.execute <<-SQL
    CREATE TABLE IF NOT EXISTS produtos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT NOT NULL,
      quantidade INTEGER DEFAULT 0,
      preco REAL DEFAULT 0.0,
      categoria TEXT,
      codigo TEXT UNIQUE,
      data_adicionado TEXT
    );
  SQL
  DB_CONN.execute <<-SQL
    CREATE TABLE IF NOT EXISTS usuarios (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE NOT NULL,
      password TEXT NOT NULL
    );
  SQL
  if DB_CONN.execute("SELECT COUNT(*) FROM usuarios WHERE username = 'admin'").first[0] == 0
    password_hash = BCrypt::Password.create('admin123')
    DB_CONN.execute("INSERT INTO usuarios (username, password) VALUES (?, ?)", ['admin', password_hash])
  end
  DB_CONN.execute <<-SQL
    CREATE TABLE IF NOT EXISTS movimentacoes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      produto_id INTEGER,
      nome_produto TEXT,
      tipo_movimentacao TEXT,
      detalhes TEXT,
      data_movimentacao TEXT,
      FOREIGN KEY (produto_id) REFERENCES produtos(id) ON DELETE SET NULL
    );
  SQL
end

setup_database

# --- Helpers ---
helpers do
  def db; DB_CONN; end
  def logged_in?; !!session[:usuario_id]; end
  def h(text); Rack::Utils.escape_html(text.to_s); end

  def registra_movimentacao(tipo, produto = nil, detalhes = '')
    produto_id = produto ? produto['id'] : nil
    nome_produto = produto ? produto['nome'] : (detalhes.match(/Arquivo: (.*)/)&.captures&.first || 'N/A')
    db.execute("INSERT INTO movimentacoes (produto_id, nome_produto, tipo_movimentacao, detalhes, data_movimentacao) VALUES (?, ?, ?, ?, ?)",
               [produto_id, nome_produto, tipo, detalhes, DateTime.now.to_s])
  end

  def processar_linha_importada(row_hash)
    row_hash = row_hash.transform_keys { |k| k.to_s.strip.downcase.gsub(/\s+/, '_').to_sym }
    nome = row_hash[:nome].to_s.strip
    return nil if nome.empty?
    quantidade = row_hash[:quantidade].to_s.to_i
    preco = row_hash[:preco].to_s.gsub(/[^\d,.]/, '').tr(',', '.').to_f
    categoria = (row_hash[:categoria] || "Geral").to_s.strip
    codigo = (row_hash[:codigo] || SecureRandom.hex(4)).to_s.strip
    [nome, quantidade, preco, categoria, codigo, Date.today.to_s]
  end

  def importar_csv(tempfile_path)
    # ... (sua lógica de importar CSV)
  end

  def importar_excel(tempfile_path)
    # ... (sua lógica de importar Excel)
  end
end

# --- Filtro de Autenticação ---
before do
  public_routes = ['/login', '/logout']
  is_public_asset = request.path_info.start_with?('/css/', '/js/', '/images/')

  unless public_routes.include?(request.path_info) || is_public_asset || logged_in?
    redirect '/login?info=' + URI.encode_www_form_component('Por favor, faça login.')
  end
end

# --- Rotas ---
get '/' do
  @valor_total = db.get_first_value("SELECT SUM(preco * quantidade) FROM produtos") || 0
  @quantidade_total = db.get_first_value("SELECT SUM(quantidade) FROM produtos") || 0
  @produtos = db.execute("SELECT * FROM produtos ORDER BY data_adicionado DESC")
  # A rota principal agora renderiza dashboard.erb
  erb :dashboard, layout: :layout
end

# --- Rotas de Login ---
get('/login') { erb :login, layout: :layout_login }
post '/login' do
  usuario = db.get_first_row("SELECT * FROM usuarios WHERE username = ?", [params[:username]])
  if usuario && BCrypt::Password.new(usuario['password']) == params[:password]
    session[:usuario_id] = usuario['id']
    session[:username] = usuario['username']
    redirect '/?sucesso=' + URI.encode_www_form_component('Login bem-sucedido!')
  else
    redirect '/login?erro=' + URI.encode_www_form_component('Usuário ou senha inválidos.')
  end
end
get('/logout'){ session.clear; redirect '/login?info=' + URI.encode_www_form_component('Você foi desconectado.') }

# --- Rotas de Produtos ---
get '/produtos' do
  @produtos = db.execute("SELECT * FROM produtos ORDER BY nome ASC")
  erb :produtos, layout: :layout
end

get('/produtos/novo'){ erb :novo_produto, layout: :layout_form }
post '/produtos/novo' do
  db.execute("INSERT INTO produtos (nome, quantidade, preco, categoria, codigo, data_adicionado) VALUES (?, ?, ?, ?, ?, ?)",
             [params[:nome], params[:quantidade].to_i, params[:preco].to_f, params[:categoria], params[:codigo], Date.today.to_s])
  produto = db.get_first_row("SELECT * FROM produtos WHERE id = last_insert_rowid()")
  registra_movimentacao('criacao', produto, "Produto criado via painel")
  redirect '/produtos?sucesso=' + URI.encode_www_form_component("Produto '#{h(produto['nome'])}' adicionado.")
end

get '/produtos/:id/editar' do
  @produto = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [params[:id]])
  redirect '/produtos' unless @produto
  erb :editar_produto, layout: :layout_form
end

post '/produtos/:id/editar' do
  produto_antigo = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [params[:id]])
  db.execute("UPDATE produtos SET nome=?, quantidade=?, preco=?, categoria=?, codigo=? WHERE id=?",
             [params[:nome], params[:quantidade].to_i, params[:preco].to_f, params[:categoria], params[:codigo], params[:id]])
  produto_novo = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [params[:id]])
  registra_movimentacao('atualizacao', produto_novo, "Atualizado: #{produto_antigo['nome']} -> #{produto_novo['nome']}")
  redirect '/produtos?sucesso=' + URI.encode_www_form_component("Produto '#{h(produto_novo['nome'])}' atualizado.")
end

post '/produtos/excluir' do
  ids = params[:produtos_ids] || []
  ids = [ids] unless ids.is_a?(Array) # Garante que ids seja um array
  ids.map!(&:to_i)

  nomes_excluidos = []
  ids.each do |id|
    produto = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [id])
    if produto
      db.execute("DELETE FROM produtos WHERE id = ?", [id])
      registra_movimentacao('exclusao', produto, "Produto excluído manualmente")
      nomes_excluidos << produto['nome']
    end
  end
  redirect '/produtos?sucesso=' + URI.encode_www_form_component("#{nomes_excluidos.count} produto(s) excluído(s).")
end

# --- Rota de Importação ---
get('/importar') { erb :importar, layout: :layout_form }
post '/importar' do
  # ... (sua lógica de importação) ...
  redirect '/produtos?sucesso=' + URI.encode_www_form_component('Arquivo importado com sucesso!')
end

# --- Rotas de API para Gráficos ---
get '/api/dados_grafico' do
  content_type :json
  dados = db.execute("SELECT categoria, SUM(preco * quantidade) as total FROM produtos WHERE categoria IS NOT NULL AND categoria != '' GROUP BY categoria")
  dados.to_json
end

get '/api/dados_grafico_quantidade' do
  content_type :json
  dados = db.execute("SELECT categoria, SUM(quantidade) as total FROM produtos WHERE categoria IS NOT NULL AND categoria != '' GROUP BY categoria")
  dados.to_json
end

# --- Outras Rotas ---
get '/relatorios' do
  query = "SELECT * FROM produtos WHERE 1=1"
  params_array = []

  # Filtro por Código
  if params[:codigo] && !params[:codigo].empty?
    query += " AND codigo LIKE ?"
    params_array << "%#{params[:codigo]}%"
  end

  # Filtro por Categoria
  if params[:categoria] && !params[:categoria][:nome].empty?
    query += " AND categoria LIKE ?"
    params_array << "%#{params[:categoria][:nome]}%"
  end

  query += " ORDER BY categoria, nome ASC"

  @produtos = db.execute(query, params_array)
  @total_produtos = @produtos.length

  # Obter todas as categorias únicas para o filtro de dropdown
  @categorias_disponiveis = db.execute("SELECT DISTINCT categoria FROM produtos WHERE categoria IS NOT NULL AND categoria != '' ORDER BY categoria ASC").map { |row| row['categoria'] }

  erb :relatorios, layout: :layout
end

get('/movimentacoes') do
  # Renomeei seu 'historico.erb' para 'movimentacoes.erb' para consistência com a rota
  @movimentacoes = db.execute("SELECT * FROM movimentacoes ORDER BY data_movimentacao DESC LIMIT 200")
  erb :movimentacoes, layout: :layout
end