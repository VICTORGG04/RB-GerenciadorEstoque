// --- Script para Filtragem Instantânea na Tabela de Relatórios ---
document.addEventListener('DOMContentLoaded', function() {
    const filterCodigoInput = document.getElementById('filter-codigo');
    const filterCategoriaSelect = document.getElementById('filter-categoria'); // Usaremos este para o JS, mas o backend também o usa
    const tabelaRelatorios = document.getElementById('tabela-relatorios');

    // Se a tabela não existe, não faz nada
    if (!tabelaRelatorios) return;

    const tableBody = tabelaRelatorios.querySelector('tbody');
    const tableRows = tableBody.querySelectorAll('tr');

    function applyFrontendFilters() {
        const codigoTerm = filterCodigoInput.value.toLowerCase();
        const categoriaSelected = filterCategoriaSelect.value.toLowerCase();

        tableRows.forEach(row => {
            // Se a linha for a mensagem "Nenhum produto encontrado", ignora
            if (row.classList.contains('text-center')) {
                row.style.display = '';
                return;
            }

            const rowCodigo = row.querySelector('.coluna-codigo')?.textContent.toLowerCase() || '';
            const rowCategoria = row.querySelector('.coluna-categoria')?.textContent.toLowerCase() || '';

            const matchesCodigo = rowCodigo.includes(codigoTerm);
            const matchesCategoria = categoriaSelected === "" || rowCategoria.includes(categoriaSelected); // Se "Todas" selecionado, sempre corresponde

            if (matchesCodigo && matchesCategoria) {
                row.style.display = '';
            } else {
                row.style.display = 'none';
            }
        });

        // Opcional: mostrar mensagem "Nenhum produto encontrado" se todas as linhas estiverem ocultas
        const visibleRows = Array.from(tableRows).filter(row => row.style.display !== 'none');
        const noResultsRow = tableBody.querySelector('.no-results-message');
        if (visibleRows.length === 0 && !noResultsRow) {
            const tr = document.createElement('tr');
            tr.innerHTML = '<td colspan="6" class="text-center no-results-message">Nenhum produto encontrado na filtragem local.</td>';
            tableBody.appendChild(tr);
        } else if (visibleRows.length > 0 && noResultsRow) {
            noResultsRow.remove();
        }
    }

    // Adiciona event listeners para a filtragem instantânea
    // O filtro de código será apenas visual no frontend
    if (filterCodigoInput) {
        filterCodigoInput.addEventListener('keyup', applyFrontendFilters);
    }
    // Para o filtro de categoria, como ele já aciona o backend, o filtro frontend será sobreposto
    // então, é mais idiomático apenas deixá-lo para o filtro de backend.
    // Se você quisesse um filtro de categoria 100% frontend (sem recarregar),
    // você removeria o "name" do select e adicionaria um eventListener aqui.
    // Mas a combinação backend + frontend é mais robusta para categorias.

    // A chamada inicial do applyFrontendFilters só faz sentido se os dados já estiverem filtrados pelo backend
    // e o input de código ou select de categoria já tiverem valores.
    // Mas como o filtro de backend é o primário, o JS só complementa para o campo de texto.
});