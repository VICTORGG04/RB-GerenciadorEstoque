document.addEventListener('DOMContentLoaded', function() {

    // =========================================================================
    // 1. Lógica de Flash Messages (Mantida)
    // =========================================================================
    function showFlashMessage(message, type) {
        // ... (código existente)
    }
    setTimeout(() => {
        const flashes = document.querySelectorAll('.flash-message');
        flashes.forEach(flash => {
            flash.style.opacity = '0';
            setTimeout(() => flash.remove(), 300);
        });
    }, 5000);

    // =========================================================================
    // 2. Lógica para a Dashboard (Gráficos APRIMORADOS)
    // =========================================================================
    function setupDashboardCharts() {
        if (typeof window.chartData === 'undefined' || !window.chartData) {
            return;
        }

        const { valorPorCategoria, quantidadePorCategoria, topProdutos, movimentacoesBaixa } = window.chartData;

        // MESTRE: Paletas de cores profissionais e temáticas
        const paletaValor = ['#4f46e5', '#7c3aed', '#db2777', '#f59e0b', '#10b981'];
        const paletaQuantidade = ['#0891b2', '#0ea5e9', '#6366f1', '#a78bfa', '#f472b6'];
        const paletaQuantidadeProdutos =['#08b238', '#bae90e', '#e363f1', '#720859', '#f472b6']
        // GRÁFICO 1: VALOR POR CATEGORIA (Doughnut)
        const ctxValor = document.getElementById('graficoValorCanvas');
        if (ctxValor && valorPorCategoria.length > 0) {
            new Chart(ctxValor, {
                type: 'doughnut',
                data: {
                    labels: valorPorCategoria.map(d => d.label),
                    datasets: [{
                        data: valorPorCategoria.map(d => d.value),
                        backgroundColor: paletaValor,
                        borderColor: 'var(--cor-fundo-card)',
                        borderWidth: 2,
                        hoverOffset: 8
                    }]
                },
                options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: 'bottom' } } }
            });
        }

        // GRÁFICO 2: QUANTIDADE POR CATEGORIA (Doughnut)
        const ctxQuantidade = document.getElementById('graficoQuantidadeCanvas');
        if (ctxQuantidade && quantidadePorCategoria.length > 0) {
            new Chart(ctxQuantidade, {
                type: 'doughnut',
                data: {
                    labels: quantidadePorCategoria.map(d => d.label),
                    datasets: [{
                        data: quantidadePorCategoria.map(d => d.quantity),
                        backgroundColor: paletaQuantidade,
                        borderColor: 'var(--cor-fundo-card)',
                        borderWidth: 2,
                        hoverOffset: 8
                    }]
                },
                options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: 'bottom' } } }
            });
        }

        // GRÁFICO 3: TOP 5 PRODUTOS (Barra Horizontal)
        const ctxBarras = document.getElementById('graficoBarrasTopProdutos');
        if (ctxBarras && topProdutos.length > 0) {
            new Chart(ctxBarras, {
                type: 'bar',
                data: {
                    labels: topProdutos.map(d => d.label),
                    datasets: [{
                        label: 'Quantidade',
                        data: topProdutos.map(d => d.quantity),
                        backgroundColor: paletaQuantidadeProdutos,
                        borderColor: 'rgb(0,0,0)',
                        borderWidth: 2
                    }]
                },
                options: {
                    indexAxis: 'y', // MESTRE: Transforma em barras horizontais
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: { legend: { display: false } },
                    scales: { y: { beginAtZero: true } }
                }
            });
        }

        // GRÁFICO 4: BAIXAS POR DIA (Linha)
        const ctxLinha = document.getElementById('graficoLinhaBaixas');
        if (ctxLinha && movimentacoesBaixa.length > 0) {
            const labels = [];
            const dataPoints = [];
            const hoje = new Date();
            for (let i = 29; i >= 0; i--) {
                const d = new Date();
                d.setDate(hoje.getDate() - i);
                const dataFormatada = d.toISOString().split('T')[0];
                labels.push(dataFormatada);
                const dadoDoDia = movimentacoesBaixa.find(item => item.date === dataFormatada);
                dataPoints.push(dadoDoDia ? dadoDoDia.baixas : 0);
            }

            new Chart(ctxLinha, {
                type: 'line',
                data: {
                    labels: labels,
                    datasets: [{
                        label: 'Baixas',
                        data: dataPoints,
                        borderColor: 'rgba(220, 53, 69, 1)',
                        backgroundColor: 'rgba(220, 53, 69, 0.2)',
                        fill: true,
                        tension: 0.3
                    }]
                },
                options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true } } }
            });
        }
    }

    // ... (O resto do seu código para as páginas de Produtos e Relatórios continua o mesmo)
    function setupProdutoPage() { /* ... */ }
    function setupRelatoriosPage() { /* ... */ }

    // Inicialização
    setupDashboardCharts();
    setupProdutoPage();
    setupRelatoriosPage();
});