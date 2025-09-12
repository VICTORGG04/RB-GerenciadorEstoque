require 'fox16'
include Fox

class Pagina < FXMainWindow
  def initialize(app)
    super(app, "Gerenciador Estoque", :width => 500, :height => 500)
  end

  def creat
    super
    show(PLACEMENT_SCREEN)
  end
end

app = FXApp.nev
Pagina.new(app)
app.create
app.run
