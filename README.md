# 📦 RB-GerenciadorEstoque

O **RB-GerenciadorEstoque** é um sistema desktop desenvolvido em **Ruby** com **FXRuby** para gerenciar produtos em estoque. Ele permite adicionar, editar, excluir e exportar produtos para CSV, além de gerar gráficos interativos que exibem **quantidade e valor por categoria**.

---

## 🚀 Funcionalidades

- ✅ Cadastro de novos produtos  
- ✅ Edição de informações existentes  
- ✅ Exclusão de múltiplos produtos  
- ✅ Exportação de dados em formato CSV  
- ✅ Visualização de gráficos dinâmicos:
  - Quantidade por categoria  
  - Valor por categoria (R$)  
- ✅ Alternância automática entre os gráficos a cada 20 segundos  

---

## 🛠️ Tecnologias Utilizadas

- **Ruby 💎** – Linguagem principal  
- **FXRuby 🎨** – Biblioteca gráfica para interfaces desktop  
- **SQLite 🗄️** – Banco de dados leve e integrado  
- **CSV 📑** – Exportação de dados  
- **Gruff 📊** – Geração de gráficos (barras)  

---

## 📂 Estrutura do Projeto

RB-GerenciadorEstoque/  
│  
├── app.rb              # Arquivo principal da aplicação  
├── cria_usuario.rb     # Script para criação de usuário  
├── gera_hash.rb        # Geração de hash para segurança  
├── estoque.db          # Banco de dados SQLite  
├── Gemfile             # Dependências do projeto  
├── Gemfile.lock        # Bloqueio de versões das gems  
├── migracao_relatorios.rb # Script para migração de relatórios  
├── views/              # Arquivos de visualização  
├── public/             # Arquivos públicos (CSS, JS, imagens)  
└── vendor/             # Dependências externas  

---

## ⚙️ Instalação

### 1. Clone o repositório
```bash
git clone https://github.com/VICTORGG04/RB-GerenciadorEstoque.git
cd RB-GerenciadorEstoque
2. Instale as dependências
bash
Copiar código
bundle install
3. Execute a aplicação
bash
Copiar código
ruby app.rb
🎮 Como Usar
Ao iniciar, a tela principal exibirá a tabela de produtos cadastrados.

Utilize os botões laterais para:

Adicionar Produto

Editar Produto

Excluir Produto(s)

Exportar CSV

Os gráficos de categorias ficam visíveis no painel inferior e alternam automaticamente a cada 20 segundos.
```


## 🤝 Contribuição
Sinta-se à vontade para abrir issues e enviar pull requests com melhorias ou correções.

## 📬 Contato
Autor: Victor Marcial

LinkedIn: https://www.linkedin.com/in/victor-marcial-7ab310373?utm_source=share&utm_campaign=share_via&utm_content=profile&utm_medium=ios_app

Email: Victor.marcial.124@ufrn.edu.br
