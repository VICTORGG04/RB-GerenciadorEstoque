📦 RB-GerenciadorEstoque

O RB-GerenciadorEstoque é um sistema desktop desenvolvido em Ruby com FXRuby para gerenciar produtos em estoque.
Ele permite adicionar, editar, excluir e exportar produtos para CSV, além de gerar gráficos interativos que exibem quantidade e valor por categoria.

🚀 Funcionalidades

✅ Cadastro de novos produtos

✅ Edição de informações existentes

✅ Exclusão de múltiplos produtos

✅ Exportação de dados em formato CSV

✅ Visualização de gráficos dinâmicos:

Quantidade por categoria

Valor por categoria (R$)

✅ Alternância automática entre os gráficos a cada 20 segundos

🛠️ Tecnologias Utilizadas

Ruby 💎 – Linguagem principal

FXRuby 🎨 – Biblioteca gráfica para interfaces desktop

SQLite 🗄️ – Banco de dados leve e integrado

CSV 📑 – Exportação de dados

Gruff 📊 – Geração de gráficos (barras)

📂 Estrutura do Projeto

RB-GerenciadorEstoque/
│
├── estoque.rb # Arquivo principal da aplicação
├── estoque.db # Banco de dados SQLite
├── Gemfile # Dependências do projeto
└── README.md # Documentação

⚙️ Instalação
1. Clone o repositório
git clone https://github.com/VICTORGG04/RB-GerenciadorEstoque.git
cd RB-GerenciadorEstoque

2. Instale as dependências
bundle install

3. Execute a aplicação
bundle exec ruby estoque.rb

🎮 Como Usar

Ao iniciar, a tela principal exibirá a tabela de produtos cadastrados.

Utilize os botões laterais para:

Adicionar Produto

Editar Produto

Excluir Produto(s)

Exportar CSV

Os gráficos de categorias ficam visíveis no painel inferior e alternam automaticamente.

📊 Preview
Tela principal (Tabela de Estoque + Gráficos)

(adicione aqui uma screenshot do programa rodando, exemplo:)


🤝 Contribuição

Sinta-se à vontade para abrir issues e enviar pull requests com melhorias ou correções.

📬 Contato

Autor: Victor Marcial

LinkedIn: Clique Aqui

Email: Victor.marcial.124@ufrn.edu.br
