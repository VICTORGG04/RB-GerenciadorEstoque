document.addEventListener('DOMContentLoaded', function() {

    // =========================================================================
    // 1. Funções Comuns e Utilitários
    // =========================================================================

    /**
     * Helper para obter parâmetros da URL.
     * @param {string} name Nome do parâmetro.
     * @returns {string|null} Valor do parâmetro ou null.
     */
    function getUrlParameter(name) {
        name = name.replace(/[\[]/, '\\[').replace(/[\]]/, '\\]');
        var regex = new RegExp('[\\?&]' + name + '=([^&#]*)');
        var results = regex.exec(location.search);
        return results === null ? '' : decodeURIComponent(results[1].replace(/\+/g, ' '));
    }

    // =========================================================================
    // 2. Lógica para a Dashboard (Gráficos)
    // =========================================================================
    function setupDashboardCharts() {
        const graficoValorContainer = document.getElementById('grafico-valor-container');
        const graficoQuantidadeContainer = document.getElementById('grafico-quantidade-container');

        if (!graficoValorContainer || !graficoQuantidadeContainer) {
            // Não estamos na dashboard ou os elementos do gráfico não existem
            return;
        }

        let currentSlideIndex = 0;
        const slides = [graficoValorContainer, graficoQuantidadeContainer];

        function showSlide(index) {
            slides.forEach((slide, i) => {
                if (i === index) {
                    slide.classList.add('active');
                } else {
                    slide.classList.remove('active');
                }
            });
        }

        function createChart(canvasId, apiUrl, title, labelCallback) {
            fetch(apiUrl)
                .then(response => response.json())
                .then(data => {
                    const ctx = document.getElementById(canvasId).getContext('2d');
                    const labels = data.map(item => item.categoria);
                    const values = data.map(item => item.total);

                    // Destruir gráfico existente se houver
                    if (Chart.getChart(ctx)) {
                        Chart.getChart(ctx).destroy();
                    }

                    new Chart(ctx, {
                        type: 'bar', // ou 'pie', ou 'doughnut'
                        data: {
                            labels: labels,
                            datasets: [{
                                label: title,
                                data: values,
                                backgroundColor: [
                                    'rgba(255, 99, 132, 0.6)', 'rgba(54, 162, 235, 0.6)',
                                    'rgba(255, 206, 86, 0.6)', 'rgba(75, 192, 192, 0.6)',
                                    'rgba(153, 102, 255, 0.6)', 'rgba(255, 159, 64, 0.6)'
                                ],
                                borderColor: [
                                    'rgba(255, 99, 132, 1)', 'rgba(54, 162, 235, 1)',
                                    'rgba(255, 206, 86, 1)', 'rgba(75, 192, 192, 1)',
                                    'rgba(153, 102, 255, 1)', 'rgba(255, 159, 64, 1)'
                                ],
                                borderWidth: 1
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            plugins: {
                                title: {
                                    display: true,
                                    text: title
                                },
                                tooltip: {
                                    callbacks: {
                                        label: labelCallback
                                    }
                                }
                            },
                            scales: {
                                y: {
                                    beginAtZero: true
                                }
                            }
                        }
                    });
                })
                .catch(error => console.error(`Erro ao carregar dados do gráfico ${title}:`, error));
        }

        // Cria os gráficos
        createChart('graficoValorCanvas', '/api/dados_grafico', 'Valor Total por Categoria',
            (context) => `Valor: R$ ${context.parsed.y.toFixed(2)}`);
        createChart('graficoQuantidadeCanvas', '/api/dados_grafico_quantidade', 'Quantidade Total por Categoria',
            (context) => `Quantidade: ${context.parsed.y}`);

        // Define um temporizador para alternar os gráficos
        setInterval(() => {
            currentSlideIndex = (currentSlideIndex + 1) % slides.length;
            showSlide(currentSlideIndex);
        }, 5000); // Altera a cada 5 segundos
    }


    // =========================================================================
    // 3. Lógica para a Página de Produtos
    // =========================================================================
    function setupProdutoPage() {
        const selectAllCheckbox = document.getElementById('select-all');
        const produtoCheckboxes = document.querySelectorAll('.produto-checkbox');
        const btnEditar = document.getElementById('btn-editar');
        const btnExcluir = document.getElementById('btn-excluir');
        const formExcluir = document.getElementById('form-excluir-selecionados');

        if (!selectAllCheckbox || !btnEditar || !btnExcluir || !formExcluir) {
            // Não estamos na página de produtos ou os elementos não existem
            return;
        }

        function updateButtonStates() {
            const selectedCheckboxes = Array.from(produtoCheckboxes).filter(cb => cb.checked);
            const hasSelection = selectedCheckboxes.length > 0;
            const singleSelection = selectedCheckboxes.length === 1;

            btnExcluir.disabled = !hasSelection;
            btnEditar.disabled = !singleSelection;

            // Anexa os IDs selecionados ao formulário de exclusão
            if (formExcluir) {
                formExcluir.querySelectorAll('input[name="produtos_ids[]"]').forEach(input => input.remove());

                selectedCheckboxes.forEach(checkbox => {
                    const hiddenInput = document.createElement('input');
                    hiddenInput.type = 'hidden';
                    hiddenInput.name = 'produtos_ids[]';
                    hiddenInput.value = checkbox.value;
                    formExcluir.appendChild(hiddenInput);
                });
            }
        }

        function handleSelectAllChange() {
            produtoCheckboxes.forEach(checkbox => {
                checkbox.checked = selectAllCheckbox.checked;
            });
            updateButtonStates();
        }

        function handleProdutoCheckboxChange() {
            // Atualiza o estado do "selecionar todos"
            selectAllCheckbox.checked = Array.from(produtoCheckboxes).every(cb => cb.checked);
            updateButtonStates();
        }

        function handleEditarClick() {
            const selectedCheckbox = Array.from(produtoCheckboxes).find(cb => cb.checked);
            if (selectedCheckbox) {
                window.location.href = `/produtos/${selectedCheckbox.value}/editar`;
            }
        }

        // Adiciona os event listeners
        selectAllCheckbox.addEventListener('change', handleSelectAllChange);
        produtoCheckboxes.forEach(checkbox => {
            checkbox.addEventListener('change', handleProdutoCheckboxChange);
        });
        btnEditar.addEventListener('click', handleEditarClick);

        // Inicializa o estado dos botões ao carregar a página
        updateButtonStates();
    }


    // =========================================================================
    // 4. Lógica para a Página de Relatórios (Filtros)
    // =========================================================================
    function setupRelatoriosPageFilters() {
        const filterCodigoInput = document.getElementById('filter-codigo');
        // O filterCategoriaSelect aciona o filtro de backend, não o frontend
        // const filterCategoriaSelect = document.getElementById('filter-categoria');
        const tabelaRelatorios = document.getElementById('tabela-relatorios');

        if (!tabelaRelatorios || !filterCodigoInput) {
            // Não estamos na página de relatórios ou os elementos não existem
            return;
        }

        const tableBody = tabelaRelatorios.querySelector('tbody');
        const tableRows = tableBody.querySelectorAll('tr');

        function applyFrontendCodigoFilter() {
            const codigoTerm = filterCodigoInput.value.toLowerCase();
            // A categoria é filtrada pelo backend
            // const categoriaSelected = filterCategoriaSelect.value.toLowerCase();

            let hasVisibleRows = false;
            tableRows.forEach(row => {
                // Ignora a linha de "Nenhum produto encontrado" se ela existir
                if (row.classList.contains('no-results-message-frontend')) {
                    row.style.display = 'none'; // Esconde temporariamente para reavaliar
                    return;
                }
                // Ignora a linha de "Nenhum produto encontrado com os filtros aplicados." que vem do backend
                if (row.querySelector('td')?.classList.contains('text-center') && row.querySelector('td')?.textContent.includes('Nenhum produto encontrado com os filtros aplicados.')) {
                    row.style.display = 'none';
                    return;
                }


                const rowCodigo = row.querySelector('.coluna-codigo')?.textContent.toLowerCase() || '';
                // const rowCategoria = row.querySelector('.coluna-categoria')?.textContent.toLowerCase() || ''; // Categoria filtrada pelo backend

                const matchesCodigo = rowCodigo.includes(codigoTerm);
                // const matchesCategoria = categoriaSelected === "" || rowCategoria.includes(categoriaSelected);

                if (matchesCodigo /* && matchesCategoria */) { // Apenas o filtro de código no frontend
                    row.style.display = '';
                    hasVisibleRows = true;
                } else {
                    row.style.display = 'none';
                }
            });

            // Gerencia a mensagem "Nenhum produto encontrado na filtragem local."
            let noResultsRow = tableBody.querySelector('.no-results-message-frontend');
            if (!hasVisibleRows) {
                if (!noResultsRow) {
                    noResultsRow = document.createElement('tr');
                    noResultsRow.innerHTML = '<td colspan="6" class="text-center no-results-message-frontend">Nenhum produto encontrado na filtragem local.</td>';
                    tableBody.appendChild(noResultsRow);
                }
                noResultsRow.style.display = ''; // Mostra a mensagem
            } else {
                if (noResultsRow) {
                    noResultsRow.remove(); // Remove a mensagem se houver resultados
                }
            }
        }

        // Adiciona event listener para a filtragem instantânea do código
        filterCodigoInput.addEventListener('keyup', applyFrontendCodigoFilter);

        // Se houver um código já pré-preenchido (vindo do backend), aplica o filtro frontend ao carregar
        if (filterCodigoInput.value) {
            applyFrontendCodigoFilter();
        }
    }


    // =========================================================================
    // 5. Inicialização (Chamada das Funções de Setup)
    // =========================================================================
    // Chamamos as funções de setup para as páginas relevantes.
    // Elas contêm verificações internas para saber se estão na página correta.
    setupDashboardCharts();
    setupProdutoPage();
    setupRelatoriosPageFilters();

    // Flash Messages
    const urlParams = new URLSearchParams(window.location.search);
    const sucesso = urlParams.get('sucesso');
    const erro = urlParams.get('erro');
    const info = urlParams.get('info');

    if (sucesso) { showFlashMessage(sucesso, 'success'); }
    if (erro) { showFlashMessage(erro, 'error'); }
    if (info) { showFlashMessage(info, 'info'); }

    function showFlashMessage(message, type) {
        // Assume que o layout.erb já tem as divs para flash messages
        // Ou você pode criar dinamicamente
        let flashDiv = document.querySelector(`.flash-message.${type}`);
        if (!flashDiv) {
            flashDiv = document.createElement('div');
            flashDiv.classList.add('flash-message', type);
            // Posição: pode ser injetado em um local específico, ex: no main content
            const mainContent = document.querySelector('.dashboard-main') || document.querySelector('.login-container');
            if (mainContent) {
                mainContent.prepend(flashDiv);
            } else {
                document.body.prepend(flashDiv);
            }
        }
        flashDiv.textContent = message;
        flashDiv.style.display = 'block';

        setTimeout(() => {
            flashDiv.style.display = 'none';
        }, 5000); // Esconde a mensagem após 5 segundos
    }
});