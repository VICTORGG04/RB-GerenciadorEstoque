# -*- coding: utf-8 -*-
require 'sinatra'
require 'sqlite3'
require 'bcrypt'
require 'securerandom'
require 'date'
require 'json'
require 'csv'
require 'roo'
require 'roo-xls'
require 'uri'
require 'google/apis/sheets_v4'
require 'googleauth'
require 'stringio'

# --- Configuração ---
enable :sessions
set :session_secret, ENV['SESSION_SECRET'] || SecureRandom.hex(64)
set :bind, '0.0.0.0'
set :port, 4567
set :database, File.join(File.dirname(__FILE__), "estoque.db")

# --- Google Sheets ---
def get_data_from_sheet
  scope = Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY

  # Caminho para o arquivo de credenciais que você salvou no projeto
  credentials_path = File.join(File.dirname(__FILE__), 'credentials.json')

  # Verifica se o arquivo existe para evitar erros
  unless File.exist?(credentials_path)
    puts "--- ERRO GRAVE: O arquivo 'credentials.json' não foi encontrado! ---"
    return [] # Retorna um array vazio para não quebrar a aplicação
  end

  # Carrega as credenciais diretamente do arquivo JSON
  creds = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open(credentials_path),
    scope: scope
  )

  service = Google::Apis::SheetsV4::SheetsService.new
  service.authorization = creds

  # ID da sua planilha
  spreadsheet_id = "1UjEW-KutO40GzwSQhheSxkzLbGJOB_wMARILiYMMK9Y"
  range = "Estoque!A2:E"

  response = service.get_spreadsheet_values(spreadsheet_id, range)

  # transforma em hashes compatíveis com seus produtos
  (response.values || []).map do |row|
    {
      codigo:     row[0],
      nome:       row[1],
      quantidade: row[2],
      preco:      row[3],
      categoria:  row[4]
    }
  end
end
# Importa os produtos lidos da planilha para o banco (upsert). Retorna um hash com contadores e erros.
def importar_produtos_da_planilha
  rows = get_data_from_sheet
  result = { inseridos: 0, atualizados: 0, ignorados: 0, erros: [] }

  rows.each_with_index do |r, idx|
    begin
      codigo = r[:codigo]
      nome = r[:nome]
      quantidade = r[:quantidade].to_i
      preco = r[:preco].to_f
      categoria = r[:categoria]

      next if codigo.nil? || codigo.empty? || nome.nil? || nome.empty?

      existing = db.get_first_row("SELECT * FROM produtos WHERE codigo = ?", codigo)

      if existing
        # Atualiza somente se houver mudança (evita movimentações redundantes)
        if existing['nome'] != nome || existing['preco'].to_f != preco || existing['categoria'].to_s != categoria.to_s || existing['quantidade'].to_i != quantidade
          db.execute("UPDATE produtos SET nome = ?, quantidade = ?, preco = ?, categoria = ?, data_atualizado = CURRENT_TIMESTAMP WHERE id = ?",
                     nome, quantidade, preco, categoria, existing['id'])
          # registra movimentação para diferença de quantidade
          if existing['quantidade'].to_i != quantidade
            tipo = quantidade > existing['quantidade'].to_i ? 'entrada' : 'baixa'
            quantidade_movimentada = (quantidade - existing['quantidade'].to_i).abs
            registra_movimentacao(tipo, existing, quantidade_movimentada, "Importado da planilha - ajuste automático (linha #{idx+2})")
          else
            registra_movimentacao('atualizacao', existing, 0, "Importado da planilha - atualização de dados (linha #{idx+2})")
          end

          result[:atualizados] += 1
        else
          result[:ignorados] += 1
        end
      else
        db.execute("INSERT INTO produtos (codigo, nome, quantidade, preco, categoria) VALUES (?, ?, ?, ?, ?)",
                   codigo, nome, quantidade, preco, categoria)
        produto_info = { 'id' => db.last_insert_row_id, 'nome' => nome }
        registra_movimentacao('entrada', produto_info, quantidade, "Importado da planilha (linha #{idx+2})")
        result[:inseridos] += 1
      end
    rescue => e
      result[:erros] << "Linha #{idx+2} (codigo: #{r[:codigo]}) - #{e.message}"
    end
  end

  result
end


# --- Helpers Globais (para acessar a conexão com o DB) ---
def db
  @db_connection ||= SQLite3::Database.new(settings.database)
  @db_connection.results_as_hash = true
  @db_connection
end

def setup_database_and_admin
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS usuarios (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT NOT NULL UNIQUE,
      password_digest TEXT NOT NULL
    );
  SQL
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS produtos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      codigo TEXT UNIQUE NOT NULL,
      nome TEXT NOT NULL,
      quantidade INTEGER NOT NULL DEFAULT 0,
      preco REAL NOT NULL DEFAULT 0.0,
      categoria TEXT,
      data_adicionado DATETIME DEFAULT CURRENT_TIMESTAMP,
      data_atualizado DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  SQL
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS movimentacoes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      produto_id INTEGER,
      produto_nome TEXT NOT NULL,
      tipo_movimentacao TEXT NOT NULL,
      quantidade INTEGER NOT NULL,
      observacao TEXT,
      data_movimentacao DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (produto_id) REFERENCES produtos(id) ON DELETE SET NULL
    );
  SQL
  unless db.get_first_value("SELECT COUNT(*) FROM usuarios WHERE email = 'admin@estoque.com'") > 0
    password_hash = BCrypt::Password.create('admin123')
    db.execute("INSERT INTO usuarios (email, password_digest) VALUES (?, ?)", ['admin@estoque.com', password_hash])
  end
end

before do
  setup_database_and_admin
  public_routes = ['/login', '/register']
  is_public_asset = request.path_info.start_with?('/css/', '/js/', '/images/', '/favicon.png')
  unless public_routes.include?(request.path_info) || is_public_asset || logged_in?
    session[:redirect_to] = request.path_info
    set_flash(:info, "Por favor, faça login para acessar esta página.")
    redirect '/login'
  end
end

# --- Helpers de Views e Lógica de Negócio ---
helpers do
  def logged_in?; !!session[:user_id]; end
  def h(text); Rack::Utils.escape_html(text.to_s); end

  def set_flash(type, message); session[type] = message; end
  def get_flash(type); message = session[type]; session[type] = nil; message; end

  def registra_movimentacao(tipo, produto_info, quantidade, observacao = "")
    db.execute("INSERT INTO movimentacoes (produto_id, produto_nome, tipo_movimentacao, quantidade, observacao) VALUES (?, ?, ?, ?, ?)",
               [produto_info['id'], produto_info['nome'], tipo, quantidade, observacao])
  rescue => e
    puts "Erro ao registrar movimentação: #{e.message}"
  end

  # Funções de dados para gráficos
  def get_resumo_estoque_data
    resumo = db.get_first_row("SELECT SUM(quantidade) AS qt, SUM(quantidade * preco) AS val FROM produtos")
    { quantidade_total: resumo['qt'] || 0, valor_total: resumo['val'] || 0.0 }
  end

  def get_valor_por_categoria_data
    (db.execute("SELECT CASE WHEN categoria IS NULL OR categoria = '' THEN 'Sem Categoria' ELSE categoria END AS cat, SUM(quantidade * preco) AS total FROM produtos GROUP BY cat ORDER BY total DESC") || []).map { |r| { label: r['cat'], value: r['total'] } }
  end

  def get_quantidade_por_categoria_data
    (db.execute("SELECT CASE WHEN categoria IS NULL OR categoria = '' THEN 'Sem Categoria' ELSE categoria END AS cat, SUM(quantidade) AS total FROM produtos GROUP BY cat ORDER BY total DESC") || []).map { |r| { label: r['cat'], quantity: r['total'] } }
  end

  def get_top_produtos_em_estoque_data(limit = 5)
    (db.execute("SELECT nome, quantidade FROM produtos ORDER BY quantidade DESC LIMIT ?", limit) || []).map { |r| { label: r['nome'], quantity: r['quantidade'] } }
  end

  def get_baixas_por_dia_data(dias = 30)
    (db.execute("SELECT strftime('%Y-%m-%d', data_movimentacao) AS dia, SUM(quantidade) AS total FROM movimentacoes WHERE tipo_movimentacao = 'baixa' AND data_movimentacao >= date('now', '-#{dias} day') GROUP BY dia ORDER BY dia ASC") || []).map { |r| { date: r['dia'], baixas: r['total'] } }
  end
end

# --- Rotas ---
get '/' do
  logged_in? ? redirect('/dashboard') : redirect('/login')
end

get '/login' do
  erb :login, layout: :layout_login
end

post '/login' do
  user = db.get_first_row("SELECT * FROM usuarios WHERE email = ?", params[:email])
  if user && BCrypt::Password.new(user['password_digest']) == params[:password]
    session[:user_id] = user['id']
    redirect_path = session.delete(:redirect_to) || '/dashboard'
    set_flash(:sucesso, "Login realizado com sucesso!")
    redirect redirect_path
  else
    set_flash(:erro, "Email ou senha incorretos.")
    redirect '/login'
  end
end

post '/logout' do
  session.clear
  set_flash(:info, "Você foi desconectado.")
  redirect '/login'
end

get '/register' do
  @erro = get_flash(:erro)
  @body_class = 'pagina-formulario-fundo'
  erb :register, layout: :layout_login
end

post '/register' do
  if params[:password] != params[:confirm_password]
    set_flash(:erro, "As senhas não coincidem.")
    redirect '/register'
  elsif params[:password].length < 6
    set_flash(:erro, "A senha deve ter no mínimo 6 caracteres.")
    redirect '/register'
  end

  existing_user = db.get_first_row("SELECT id FROM usuarios WHERE email = ?", params[:email])
  if existing_user
    set_flash(:erro, "Este email já está cadastrado.")
    redirect '/register'
  end

  password_digest = BCrypt::Password.create(params[:password])
  begin
    db.execute("INSERT INTO usuarios (email, password_digest) VALUES (?, ?)", params[:email], password_digest)
    set_flash(:sucesso, "Registro realizado com sucesso! Faça login.")
    redirect '/login'
  rescue SQLite3::Exception => e
    set_flash(:erro, "Erro ao registrar usuário: #{e.message}")
    redirect '/register'
  end
end

# Rota do Dashboard
get '/dashboard' do
  resumo = get_resumo_estoque_data
  @quantidade_total = resumo[:quantidade_total]
  @valor_total = resumo[:valor_total]
  @valor_por_categoria = get_valor_por_categoria_data
  @quantidade_por_categoria = get_quantidade_por_categoria_data
  @top_produtos = get_top_produtos_em_estoque_data(5)
  @movimentacoes_baixa_dia = get_baixas_por_dia_data(30)
  @produtos_recentes = db.execute("SELECT *, strftime('%d/%m/%Y', data_adicionado) as data_adicionado_formatada FROM produtos ORDER BY data_adicionado DESC LIMIT 5")
  erb :dashboard, layout: :layout
end

# --- Rotas para integração com Google Sheets ---
# Página simples que mostra um botão para importar (pode ser usada em views)
get '/sheets' do
  erb :sheets_import, layout: :layout
end

# Rota que executa a importação (POST para evitar acionamento acidental)
post '/sheets/import' do
  result = importar_produtos_da_planilha
  msg = []
  msg << "#{result[:inseridos]} inserido(s)" if result[:inseridos] > 0
  msg << "#{result[:atualizados]} atualizado(s)" if result[:atualizados] > 0
  msg << "#{result[:ignorados]} ignorado(s)" if result[:ignorados] > 0
  msg << "#{result[:erros].count} erro(s)" if result[:erros].any?

  if result[:erros].any?
    set_flash(:info, (msg + ["Erros: ", result[:erros].join(' | ')]).join(' - '))
  else
    set_flash(:sucesso, msg.join(' - '))
  end
  redirect '/produtos'
end

# --- Rotas de Produtos ---
get '/produtos' do
  @produtos = db.execute("SELECT *, strftime('%d/%m/%Y', data_adicionado) as data_adicionado_formatada FROM produtos ORDER BY nome ASC")
  erb :produtos, layout: :layout
end
get('/produtos/novo') { erb :novo_produto, layout: :layout_form }

post '/produtos/novo' do
  nome = params[:nome]
  quantidade = params[:quantidade].to_i
  preco = params[:preco].to_f
  categoria = params[:categoria]
  codigo = params[:codigo]

  if nome.empty? || quantidade < 0 || preco < 0 || codigo.empty?
    set_flash(:erro, "Por favor, preencha todos os campos obrigatórios e use valores válidos.")
    redirect '/produtos/novo'
  end

  begin
    db.execute("INSERT INTO produtos (codigo, nome, quantidade, preco, categoria) VALUES (?, ?, ?, ?, ?)",
               codigo, nome, quantidade, preco, categoria)

    produto_info = { 'id' => db.last_insert_row_id, 'nome' => nome }
    registra_movimentacao('entrada', produto_info, quantidade, "Novo produto adicionado")

    set_flash(:sucesso, "Produto '#{nome}' adicionado com sucesso!")
    redirect '/produtos'
  rescue SQLite3::ConstraintException => e
    if e.message.include?("UNIQUE constraint failed: produtos.codigo")
      set_flash(:erro, "Erro: Já existe um produto com o código '#{codigo}'.")
    else
      set_flash(:erro, "Erro ao adicionar produto: #{e.message}")
    end
    redirect '/produtos/novo'
  rescue => e
    set_flash(:erro, "Erro inesperado ao adicionar produto: #{e.message}")
    redirect '/produtos/novo'
  end
end


#EDITADO POR VICTOR
get '/produtos/:id/editar' do
  @produto = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [params[:id]])
  redirect '/produtos' unless @produto
  erb :editar_produto, layout: :layout_form
end
post '/produtos/:id/editar' do
  produto_id = params[:id]
  nome = params[:nome]
  quantidade = params[:quantidade].to_i
  preco = params[:preco].to_f
  categoria = params[:categoria]
  codigo = params[:codigo]

  if nome.empty? || quantidade < 0 || preco < 0 || codigo.empty?
    set_flash(:erro, "Por favor, preencha todos os campos obrigatórios e use valores válidos.")
    redirect "/produtos/#{produto_id}/editar"
  end

  existing_product = db.get_first_row("SELECT id FROM produtos WHERE codigo = ? AND id != ?", codigo, produto_id)
  if existing_product
    set_flash(:erro, "Erro: Já existe outro produto com o código '#{codigo}'.")
    redirect "/produtos/#{produto_id}/editar"
  end

  begin
    old_produto = db.get_first_row("SELECT * FROM produtos WHERE id = ?", produto_id)
    if old_produto
      old_quantidade = old_produto['quantidade']
      new_quantidade = quantidade

      db.execute("UPDATE produtos SET codigo = ?, nome = ?, quantidade = ?, preco = ?, categoria = ?, data_atualizado = CURRENT_TIMESTAMP WHERE id = ?",
                 codigo, nome, new_quantidade, preco, categoria, produto_id)

      if new_quantidade != old_quantidade
        tipo = if new_quantidade > old_quantidade
                 'entrada'
               elsif new_quantidade < old_quantidade
                 'baixa'
               else
                 'ajuste'
               end
        quantidade_movimentada = (new_quantidade - old_quantidade).abs
        registra_movimentacao(tipo, old_produto, quantidade_movimentada, "Ajuste na atualização do produto (cód: #{codigo})")
      else
        registra_movimentacao('atualizacao', old_produto, 0, "Produto atualizado (cód: #{codigo})")
      end

      set_flash(:sucesso, "Produto '#{nome}' atualizado com sucesso!")
      redirect '/produtos'
    else
      set_flash(:erro, "Produto não encontrado para atualização.")
      redirect '/produtos'
    end
  rescue SQLite3::Exception => e
    set_flash(:erro, "Erro ao atualizar produto: #{e.message}")
    redirect "/produtos/#{produto_id}/editar"
  rescue => e
    set_flash(:erro, "Erro inesperado ao atualizar produto: #{e.message}")
    redirect "/produtos/#{produto_id}/editar"
  end
end

post '/produtos/excluir_selecionados' do
  produtos_ids = params[:produtos_ids] || []

  if produtos_ids.empty?
    set_flash(:erro, "Nenhum produto selecionado para exclusão.")
    redirect '/produtos'
  end

  deleted_count = 0
  db.transaction do
    produtos_ids.each do |id|
      begin
        produto = db.get_first_row("SELECT * FROM produtos WHERE id = ?", id)
        if produto
          db.execute("DELETE FROM produtos WHERE id = ?", id)
          registra_movimentacao('exclusao', produto, produto['quantidade'], "Produto '#{produto['nome']}' excluído (cód: #{produto['codigo']})")
          deleted_count += 1
        end
      rescue SQLite3::Exception => e
        puts "Erro ao excluir produto #{id}: #{e.message}"
      end
    end
  end

  if deleted_count > 0
    set_flash(:sucesso, "#{deleted_count} produto(s) excluído(s) com sucesso!")
  elsif produtos_ids.any? && deleted_count == 0
    set_flash(:erro, "Erro ao excluir os produtos selecionados ou eles já não existiam.")
  end
  redirect '/produtos'
end

# --- Rotas de Importação ---
get('/importar') { erb :importar, layout: :layout_form }

post '/importar' do
  file = params[:file]

  if file && file[:tempfile] && file[:filename]
    filename = file[:filename]
    tempfile = file[:tempfile]
    file_extension = File.extname(filename).downcase

    result = { sucessos: 0, erros: [] }
    case file_extension
    when '.csv'
      result = importar_csv(tempfile.path, filename)
    when '.xlsx', '.xls'
      result = importar_excel(tempfile.path, filename)
    else
      set_flash(:erro, "Tipo de arquivo não suportado: #{file_extension}. Por favor, envie um arquivo CSV ou Excel.")
      redirect '/importar'
    end

    message = []
    message << "#{result[:sucessos]} produtos importados com sucesso." if result[:sucessos] > 0
    message << "#{result[:erros].count} erros encontrados durante a importação." if !result[:erros].empty?

    if !result[:erros].empty?
      puts "Erros de Importação em #{filename}:"
      result[:erros].each { |e| puts " - #{e}" }
    end

    if message.empty? && result[:erros].empty?
      set_flash(:info, "Nenhum produto foi processado no arquivo. Verifique se o arquivo está formatado corretamente.")
    elsif !result[:erros].empty?
      set_flash(:info, message.join(' '))
    else
      set_flash(:sucesso, message.join(' '))
    end

    redirect '/produtos'
  else
    set_flash(:erro, "Nenhum arquivo enviado ou erro no upload.")
    redirect '/importar'
  end
end

# --- Rotas de Relatórios ---
get '/relatorios' do
  @sucesso = get_flash(:sucesso)
  @erro = get_flash(:erro)
  @info = get_flash(:info)

  query = <<-SQL
    SELECT
      id,
      codigo,
      nome,
      quantidade,
      preco,
      categoria,
      strftime('%d/%m/%Y %H:%M', data_adicionado) AS data_adicionado_formatada,
      strftime('%d/%m/%Y %H:%M', data_atualizado) AS data_atualizado_formatada
    FROM produtos
    WHERE 1=1
  SQL
  query_params = []

  if params[:codigo] && !params[:codigo].empty?
    query += " AND (codigo LIKE ? OR nome LIKE ?)"
    query_params << "%#{params[:codigo]}%"
    query_params << "%#{params[:codigo]}%"
  end

  if params[:categoria] && !params[:categoria].empty?
    categoria_param = params[:categoria]
    if categoria_param.is_a?(String) && categoria_param.start_with?('{')
      begin
        parsed_categoria = JSON.parse(categoria_param)
        categoria_value = parsed_categoria['nome'] || parsed_categoria['categoria'] || categoria_param
      rescue JSON::ParserError
        categoria_value = categoria_param
      end
    elsif categoria_param.is_a?(Hash)
      categoria_value = categoria_param['nome'] || categoria_param['categoria']
    else
      categoria_value = categoria_param
    end

    if categoria_value && !categoria_value.to_s.empty? && categoria_value.to_s != "Todas"
      query += " AND categoria = ?"
      query_params << categoria_value.to_s
    end
  end

  query += " ORDER BY data_adicionado DESC"

  @produtos_filtrados = db.execute(query, *query_params) || []
  @categorias_disponiveis = (db.execute("SELECT DISTINCT categoria FROM produtos WHERE categoria IS NOT NULL AND categoria != '' ORDER BY categoria ASC") || []).map { |row| row['categoria'] }
  @categorias_disponiveis.unshift("Todas")

  if @produtos_filtrados.empty? && (params[:codigo] || params[:categoria])
    @nenhum_produto_encontrado_backend = "Nenhum produto encontrado com os filtros aplicados."
  end

  erb :relatorios, layout: :layout
end

# --- Rotas de Movimentações ---
get('/movimentacoes') do
  @movimentacoes = db.execute("SELECT *, strftime('%d/%m/%Y %H:%M', data_movimentacao) as data_formatada FROM movimentacoes ORDER BY data_movimentacao DESC LIMIT 200")
  erb :movimentacoes, layout: :layout
end

post '/movimentacoes/novo' do
  produto_id = params[:produto_id].to_i
  tipo = params[:tipo_movimentacao]
  quantidade = params[:quantidade].to_i
  observacao = params[:observacao].to_s.strip

  produto = db.get_first_row("SELECT * FROM produtos WHERE id = ?", produto_id)

  if !produto
    set_flash(:erro, 'Produto não encontrado.')
    redirect '/movimentacoes'
  elsif quantidade <= 0
    set_flash(:erro, 'Quantidade deve ser maior que zero.')
    redirect '/movimentacoes'
  end

  nova_quantidade_produto = produto['quantidade']

  begin
    db.transaction do
      if tipo == 'entrada'
        nova_quantidade_produto += quantidade
        db.execute("UPDATE produtos SET quantidade = ? WHERE id = ?", nova_quantidade_produto, produto_id)
        registra_movimentacao('entrada', produto, quantidade, "Entrada de #{quantidade} unidades. Obs: #{observacao}")
        set_flash(:sucesso, "Entrada de #{quantidade} unidades registrada para #{produto['nome']}.")
      elsif tipo == 'saida'
        if nova_quantidade_produto >= quantidade
          nova_quantidade_produto -= quantidade
          db.execute("UPDATE produtos SET quantidade = ? WHERE id = ?", nova_quantidade_produto, produto_id)
          registra_movimentacao('baixa', produto, quantidade, "Saída de #{quantidade} unidades. Obs: #{observacao}")
          set_flash(:sucesso, "Saída de #{quantidade} unidades registrada para #{produto['nome']}.")
        else
          set_flash(:erro, "Estoque insuficiente para '#{produto['nome']}'. Disponível: #{produto['quantidade']}.")
        end
      else
        set_flash(:erro, 'Tipo de movimentação inválido.')
      end
    end # End transaction
  rescue SQLite3::Exception => e
    set_flash(:erro, "Erro ao registrar movimentação: #{e.message}")
  rescue => e
    set_flash(:erro, "Erro inesperado ao registrar movimentação: #{e.message}")
  end
  redirect '/movimentacoes'
end

post '/movimentacoes/excluir/:id' do
  id = params[:id]
  mov = db.get_first_row("SELECT * FROM movimentacoes WHERE id = ?", id)
  if mov
    db.execute("DELETE FROM movimentacoes WHERE id = ?", id)
    set_flash(:sucesso, "Movimentação de #{mov['produto_nome']} excluída.")
  else
    set_flash(:erro, 'Movimentação não encontrada.')
  end
  redirect '/movimentacoes'
end

# --- Páginas de erro customizadas ---
not_found do
  @message = "A página que você tentou acessar não existe."
  erb :error, layout: :layout
end

error do
  @message = "Ocorreu um erro no servidor: #{env['sinatra.error'].message}"
  erb :error, layout: :layout
end