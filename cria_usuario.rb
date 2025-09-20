# -*- coding: utf-8 -*-
require 'sqlite3'
require 'bcrypt'

# --- Configuração do Banco de Dados ---
# Garante que o script use o mesmo arquivo de banco de dados do seu app.rb
DB_PATH = File.join(File.dirname(__FILE__), "estoque.db")

# Conecta ao banco de dados
db = SQLite3::Database.new(DB_PATH)
db.results_as_hash = true # Opcional, mas consistente com o app.rb

# Garante que a tabela de usuários exista, caso este script seja executado antes do app.rb
# (É sempre bom ter essa verificação em scripts de gerenciamento de DB)
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS usuarios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT NOT NULL UNIQUE,
    password_digest TEXT NOT NULL
  );
SQL

puts "--- Ferramenta de Criação de Usuário ---"

print "Digite o EMAIL do novo usuário: "
email = gets.chomp.strip.downcase # Normaliza para evitar problemas de case e espaços

print "Digite a senha para #{email}: "
password = gets.chomp

# Validação básica de senha
if password.length < 6
  puts "Erro: A senha deve ter no mínimo 6 caracteres."
  exit # Sai do script
end

hashed_password = BCrypt::Password.create(password)

begin
  # CORRIGIDO: usa as colunas 'email' e 'password_digest'
  db.execute("INSERT INTO usuarios (email, password_digest) VALUES (?, ?)", [email, hashed_password])
  puts "\nUsuário '#{email}' criado com sucesso!"
rescue SQLite3::ConstraintException => e
  if e.message.include?("UNIQUE constraint failed: usuarios.email")
    puts "\nErro: O email '#{email}' já existe. Por favor, escolha outro."
  else
    puts "\nErro desconhecido ao criar usuário: #{e.message}"
  end
rescue => e
  puts "\nOcorreu um erro inesperado: #{e.message}"
ensure
  db.close if db # Garante que a conexão com o banco de dados seja fechada
end