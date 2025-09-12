require 'sqlite3'
require 'bcrypt'

DB_PATH = File.join(File.dirname(__FILE__), "estoque.db")
db = SQLite3::Database.new(DB_PATH)

puts "--- Ferramenta de Criação de Usuário ---"
print "Digite o nome de usuário: "
username = gets.chomp

print "Digite a senha: "
password = gets.chomp

hashed_password = BCrypt::Password.create(password)

begin
  db.execute("INSERT INTO usuarios (username, password) VALUES (?, ?)", [username, hashed_password])
  puts "\nUsuário '#{username}' criado com sucesso!"
rescue SQLite3::ConstraintException
  puts "\nErro: O nome de usuário '#{username}' já existe."
end