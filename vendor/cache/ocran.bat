@ECHO OFF
TITLE Gerando Executável
ECHO Iniciando o processo de empacotamento...
ECHO.

REM O comando abaixo chama o OCRAN com todos os argumentos
REM para criar o executável do seu projeto Sinatra.

C:\Ruby34-x64\bin\ocran.bat app.rb --add-all-files --gemfile Gemfile --no-dep-run --console --gem-full

ECHO.
ECHO Processo concluido. Pressione qualquer tecla para fechar.
PAUSE >NUL