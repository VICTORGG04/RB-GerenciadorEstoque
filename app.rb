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
require 'uri' # Necessário para URI.encode_www_form_component

# --- Configuração ---
enable :sessions
set :session_secret, SecureRandom.hex(64) # Gere uma chave segura para produção!
set :bind, '0.0.0.0'
set :port, 4567

DB_PATH = File.join(File.dirname(__FILE__), "estoque.db")
DB_CONN = SQLite3::Database.new(DB_PATH)
DB_CONN.results_as_hash = true # Retorna resultados como Hash

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

  # Função para registrar movimentações, adaptada para seus campos
  def registra_movimentacao(tipo, produto = nil, detalhes = '')
    produto_id = produto ? produto['id'] : nil
    # Tenta obter o nome do produto do hash, ou do detalhes, ou 'N/A'
    nome_produto = produto ? produto['nome'] : (detalhes.match(/Arquivo: (.*)/)&.captures&.first || 'N/A')
    db.execute("INSERT INTO movimentacoes (produto_id, nome_produto, tipo_movimentacao, detalhes, data_movimentacao) VALUES (?, ?, ?, ?, ?)",
               [produto_id, nome_produto, tipo, detalhes, DateTime.now.to_s])
  end

  # Função para processar uma linha de dados importada
  def processar_linha_importada(row_hash, row_num)
    # Transforma chaves para símbolos em minúsculas e remove espaços
    row_hash = row_hash.transform_keys { |k| k.to_s.strip.downcase.gsub(/\s+/, '_').to_sym }

    nome = row_hash[:nome].to_s.strip
    quantidade = row_hash[:quantidade].to_s.to_i
    # Lida com formatos de preço com vírgula ou ponto
    preco = row_hash[:preco].to_s.gsub(/[^\d,\.]/, '').tr(',', '.').to_f
    categoria = (row_hash[:categoria] || "Geral").to_s.strip
    codigo = (row_hash[:codigo] || SecureRandom.hex(4)).to_s.strip # Gera código se não houver

    # Validação dos dados
    if nome.empty? || quantidade < 0 || preco < 0
      return { error: "Linha ##{row_num}: Dados inválidos ou incompletos (Nome: '#{nome}', Código: '#{codigo}')." }
    end

    begin
      db.execute("INSERT INTO produtos (nome, quantidade, preco, categoria, codigo, data_adicionado) VALUES (?, ?, ?, ?, ?, ?)",
                 [nome, quantidade, preco, categoria, codigo, Date.today.to_s])
      produto = db.get_first_row("SELECT * FROM produtos WHERE id = last_insert_rowid()")
      registra_movimentacao('importacao', produto, "Importado via arquivo")
      return { success: true }
    rescue SQLite3::ConstraintException => e
      if e.message.include?("UNIQUE constraint failed: produtos.codigo")
        return { error: "Linha ##{row_num}: Produto com código '#{codigo}' já existe. Ignorado." }
      else
        return { error: "Linha ##{row_num}: Erro DB ao inserir '#{nome}' (Código: '#{codigo}'): #{e.message}" }
      end
    rescue => e
      return { error: "Linha ##{row_num}: Erro desconhecido ao inserir '#{nome}' (Código: '#{codigo}'): #{e.message}" }
    end
  end


  # Funções de Importação (agora com a lógica completa)
  def importar_csv(tempfile_path, filename)
    erros = []
    sucessos = 0

    # Adicionando encoding: 'UTF-8' e force_quotes: true para melhor compatibilidade
    CSV.foreach(tempfile_path, headers: true, col_sep: ',', encoding: 'UTF-8') do |row|
      result = processar_linha_importada(row.to_h, $.) # $ é o número da linha atual
      if result[:success]
        sucessos += 1
      elsif result[:error]
        erros << result[:error]
      end
    end
    registra_movimentacao('importacao_massa', nil, "CSV: #{filename} - Sucessos: #{sucessos}, Erros: #{erros.count}")
    { sucessos: sucessos, erros: erros }
  end

  def importar_excel(tempfile_path, filename)
    erros = []
    sucessos = 0

    begin
      spreadsheet = Roo::Spreadsheet.open(tempfile_path)
      sheet = spreadsheet.sheet(0) # Pega a primeira planilha (índice 0)

      headers = sheet.row(1).map { |header| header.to_s.strip } # Cabeçalhos da primeira linha

      (2..sheet.last_row).each do |row_num| # Itera a partir da segunda linha
        row_data = Hash[headers.zip(sheet.row(row_num))] # Mapeia os dados da linha para os cabeçalhos

        result = processar_linha_importada(row_data, row_num)
        if result[:success]
          sucessos += 1
        elsif result[:error]
          erros << result[:error]
        end
      end
    rescue => e
      erros << "Erro ao processar arquivo Excel '#{filename}': #{e.message}"
    end
    registra_movimentacao('importacao_massa', nil, "Excel: #{filename} - Sucessos: #{sucessos}, Erros: #{erros.count}")
    { sucessos: sucessos, erros: erros }
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
# --- ALTEREI A LOGICA DE IMAGEM DE FUNDO E O CARD ---
get('/produtos/novo') do
  @body_class = 'pagina-formulario-fundo'
  erb :novo_produto, layout: :layout_form
end
post '/produtos/novo' do
  nome = params[:nome]
  quantidade = params[:quantidade].to_i
  preco = params[:preco].to_f
  categoria = params[:categoria]
  codigo = params[:codigo]

  if nome.empty? || quantidade < 0 || preco < 0 || codigo.empty?
    redirect '/produtos/novo?erro=' + URI.encode_www_form_component('Por favor, preencha todos os campos obrigatórios e use valores válidos.')
  end

  begin
    db.execute("INSERT INTO produtos (nome, quantidade, preco, categoria, codigo, data_adicionado) VALUES (?, ?, ?, ?, ?, ?)",
               [nome, quantidade, preco, categoria, codigo, Date.today.to_s])
    produto = db.get_first_row("SELECT * FROM produtos WHERE id = last_insert_rowid()")
    registra_movimentacao('criacao', produto, "Produto criado via painel")
    redirect '/produtos?sucesso=' + URI.encode_www_form_component("Produto '#{h(produto['nome'])}' adicionado.")
  rescue SQLite3::ConstraintException => e
    if e.message.include?("UNIQUE constraint failed: produtos.codigo")
      redirect '/produtos/novo?erro=' + URI.encode_www_form_component("Erro: Já existe um produto com o código '#{codigo}'.")
    else
      redirect '/produtos/novo?erro=' + URI.encode_www_form_component("Erro ao adicionar produto: #{e.message}")
    end
  end
end

get '/produtos/:id/editar' do
  @produto = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [params[:id]])

  unless @produto # Melhorar a verificação de produto nulo com uma mensagem
    redirect '/produtos?erro=' + URI.encode_www_form_component('Produto não encontrado para edição.')
  end

  @body_class = 'pagina-formulario-fundo' # <<< ADICIONE ESTA LINHA
  erb :editar_produto, layout: :layout_form
end

post '/produtos/:id/editar' do
  id = params[:id]
  nome = params[:nome]
  quantidade = params[:quantidade].to_i
  preco = params[:preco].to_f
  categoria = params[:categoria]
  codigo = params[:codigo]

  if nome.empty? || quantidade < 0 || preco < 0 || codigo.empty?
    redirect "/produtos/#{id}/editar?erro=" + URI.encode_www_form_component('Por favor, preencha todos os campos obrigatórios e use valores válidos.')
  end

  produto_antigo = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [id])
  begin
    db.execute("UPDATE produtos SET nome=?, quantidade=?, preco=?, categoria=?, codigo=? WHERE id=?",
               [nome, quantidade, preco, categoria, codigo, id])
    produto_novo = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [id])
    registra_movimentacao('atualizacao', produto_novo, "Atualizado: #{produto_antigo['nome']} -> #{produto_novo['nome']}")
    redirect '/produtos?sucesso=' + URI.encode_www_form_component("Produto '#{h(produto_novo['nome'])}' atualizado.")
  rescue SQLite3::ConstraintException => e
    if e.message.include?("UNIQUE constraint failed: produtos.codigo")
      redirect "/produtos/#{id}/editar?erro=" + URI.encode_www_form_component("Erro: Já existe um produto com o código '#{codigo}'.")
    else
      redirect "/produtos/#{id}/editar?erro=" + URI.encode_www_form_component("Erro ao atualizar produto: #{e.message}")
    end
  end
end

post '/produtos/excluir' do
  ids = params[:produtos_ids] || []
  ids = [ids] unless ids.is_a?(Array) # Garante que ids seja um array
  ids.map!(&:to_i)

  if ids.empty?
    redirect '/produtos?info=' + URI.encode_www_form_component('Nenhum produto selecionado para exclusão.')
  end

  nomes_excluidos = []
  begin
    db.transaction do
      ids.each do |id|
        produto = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [id])
        if produto
          db.execute("DELETE FROM produtos WHERE id = ?", [id])
          registra_movimentacao('exclusao', produto, "Produto excluído manualmente")
          nomes_excluidos << produto['nome']
        end
      end
    end
    redirect '/produtos?sucesso=' + URI.encode_www_form_component("#{nomes_excluidos.count} produto(s) excluído(s).")
  rescue => e
    redirect '/produtos?erro=' + URI.encode_www_form_component("Erro ao excluir produtos: #{e.message}")
  end
end

# --- Rota de Importação (ATUALIZADA) ---
get('/importar') do
  @body_class = 'pagina-formulario-fundo'
  erb :importar, layout: :layout_form
end

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
      redirect '/importar?erro=' + URI.encode_www_form_component("Tipo de arquivo não suportado: #{file_extension}. Por favor, envie um arquivo CSV ou Excel.")
    end

    message = []
    message << "#{result[:sucessos]} produtos importados com sucesso." if result[:sucessos] > 0
    message << "Atenção: #{result[:erros].count} erros encontrados. Detalhes: #{result[:erros].join('; ')}" if !result[:erros].empty?

    if message.empty?
      redirect '/produtos?info=' + URI.encode_www_form_component('Nenhum produto foi importado. Verifique o arquivo e tente novamente.')
    else
      # Decide se é sucesso ou info baseado na existência de erros
      if result[:erros].empty?
        redirect '/produtos?sucesso=' + URI.encode_www_form_component(message.join(' '))
      else
        redirect '/produtos?info=' + URI.encode_www_form_component(message.join(' ')) # Usa info se houver erros, mesmo com sucessos
      end
    end
  else
    redirect '/importar?erro=' + URI.encode_www_form_component('Nenhum arquivo foi enviado ou houve um erro no upload.')
  end
end

# --- Rotas de API para Gráficos (Dashboard) ---
get '/dashboard' do # Rota da dashboard separada do '/'
  @valor_total = db.get_first_value("SELECT SUM(preco * quantidade) FROM produtos") || 0
  @quantidade_total = db.get_first_value("SELECT SUM(quantidade) FROM produtos") || 0

  # Preparar dados para top 5, garantindo que não falhe se não houver produtos
  @top_5_valor = db.execute("SELECT nome, (quantidade * preco) AS valor_total FROM produtos ORDER BY valor_total DESC LIMIT 5")
  @top_5_quantidade = db.execute("SELECT nome, quantidade FROM produtos ORDER BY quantidade DESC LIMIT 5")

  erb :dashboard, layout: :layout
end

get '/api/dados_grafico' do
  content_type :json
  # Usa COALESCE para tratar categorias nulas como 'Outros'
  dados = db.execute("SELECT COALESCE(categoria, 'Outros') AS categoria, SUM(preco * quantidade) AS total FROM produtos GROUP BY COALESCE(categoria, 'Outros') ORDER BY total DESC")
  dados.to_json
end

get '/api/dados_grafico_quantidade' do
  content_type :json
  # Usa COALESCE para tratar categorias nulas como 'Outros'
  dados = db.execute("SELECT COALESCE(categoria, 'Outros') AS categoria, SUM(quantidade) AS total FROM produtos GROUP BY COALESCE(categoria, 'Outros') ORDER BY total DESC")
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
  if params[:categoria] && params[:categoria][:nome] && !params[:categoria][:nome].empty? # Ajustado para sua estrutura de params
    query += " AND categoria LIKE ?"
    params_array << "%#{params[:categoria][:nome]}%"
  end

  query += " ORDER BY categoria, nome ASC"

  @produtos = db.execute(query, params_array)
  @total_produtos = @produtos.length

  # Obter todas as categorias únicas para o filtro de dropdown
  @categorias_disponiveis = db.execute("SELECT DISTINCT categoria FROM produtos WHERE categoria IS NOT NULL AND categoria != '' ORDER BY categoria ASC").map { |row| row['categoria'] }

  # Adiciona uma mensagem se não houver produtos após o filtro, para ser exibida no ERB
  if @produtos.empty? && (params[:codigo] || (params[:categoria] && params[:categoria][:nome]))
    @nenhum_produto_encontrado_backend = "Nenhum produto encontrado com os filtros aplicados."
  end

  erb :relatorios, layout: :layout
end

get('/movimentacoes') do
  @movimentacoes = db.execute("SELECT * FROM movimentacoes ORDER BY data_movimentacao DESC LIMIT 200")
  # Para o formulário de adicionar movimentação, talvez você precise de uma lista de produtos
  @produtos_disponiveis = db.execute("SELECT id, nome, codigo FROM produtos ORDER BY nome ASC")
  erb :movimentacoes, layout: :layout
end

# Rota para adicionar nova movimentação (Exemplo - adapte se tiver um formulário)
post '/movimentacoes/novo' do
  produto_id = params[:produto_id].to_i
  tipo = params[:tipo_movimentacao] # 'entrada' ou 'saida'
  quantidade = params[:quantidade].to_i
  detalhes = params[:detalhes]

  produto = db.get_first_row("SELECT * FROM produtos WHERE id = ?", [produto_id])

  if !produto
    redirect '/movimentacoes?erro=' + URI.encode_www_form_component('Produto não encontrado.')
  elsif quantidade <= 0
    redirect '/movimentacoes?erro=' + URI.encode_www_form_component('Quantidade deve ser maior que zero.')
  end

  nova_quantidade_produto = produto['quantidade']

  if tipo == 'entrada'
    nova_quantidade_produto += quantidade
    db.execute("UPDATE produtos SET quantidade = ? WHERE id = ?", [nova_quantidade_produto, produto_id])
    registra_movimentacao('entrada', produto, "Entrada de #{quantidade} unidades. Detalhes: #{detalhes}")
    redirect '/movimentacoes?sucesso=' + URI.encode_www_form_component("Entrada registrada para #{produto['nome']}.")
  elsif tipo == 'saida'
    if nova_quantidade_produto >= quantidade
      nova_quantidade_produto -= quantidade
      db.execute("UPDATE produtos SET quantidade = ? WHERE id = ?", [nova_quantidade_produto, produto_id])
      registra_movimentacao('saida', produto, "Saída de #{quantidade} unidades. Detalhes: #{detalhes}")
      redirect '/movimentacoes?sucesso=' + URI.encode_www_form_component("Saída registrada para #{produto['nome']}.")
    else
      redirect '/movimentacoes?erro=' + URI.encode_www_form_component("Estoque insuficiente para '#{produto['nome']}'. Disponível: #{produto['quantidade']}.")
    end
  else
    redirect '/movimentacoes?erro=' + URI.encode_www_form_component('Tipo de movimentação inválido.')
  end
end

# Rota para excluir movimentação
post '/movimentacoes/excluir/:id' do
  id = params[:id]
  mov = db.get_first_row("SELECT * FROM movimentacoes WHERE id = ?", [id])
  if mov
    db.execute("DELETE FROM movimentacoes WHERE id = ?", [id])
    # Não registra a exclusão da movimentação de registro, para evitar loop
    redirect '/movimentacoes?sucesso=' + URI.encode_www_form_component("Movimentação de #{mov['nome_produto']} excluída.")
  else
    redirect '/movimentacoes?erro=' + URI.encode_www_form_component('Movimentação não encontrada.')
  end
end