require 'sqlite3'

DB_PATH = File.join(File.dirname(__FILE__), "estoque.db")
db = SQLite3::Database.new(DB_PATH)

puts "Adicionando tabela de movimentações ao banco de dados..."

db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS movimentacoes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    produto_id INTEGER,
    nome_produto TEXT,
    tipo_movimentacao TEXT, -- "CRIACAO", "ATUALIZACAO", "EXCLUSAO"
    detalhes TEXT,
    data_movimentacao TEXT
  );
SQL

puts "Tabela 'movimentacoes' criada com sucesso!"
puts "Seu banco de dados está pronto para os relatórios diários."