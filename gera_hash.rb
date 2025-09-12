require 'bcrypt'

senha = "admin123"
hash = BCrypt::Password.create(senha)
puts "Senha: #{senha}"
puts "Hash: #{hash}"
