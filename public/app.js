document.addEventListener('DOMContentLoaded', () => {
    const checkboxes = document.querySelectorAll('.produto-checkbox');
    const btnEditar = document.getElementById('btn-editar');
    const btnExcluir = document.getElementById('btn-excluir');

    function atualizarBotoes() {
        const selecionados = document.querySelectorAll('.produto-checkbox:checked');
        if (btnExcluir) { btnExcluir.disabled = selecionados.length === 0; }
        if (btnEditar) {
            if (selecionados.length === 1) {
                btnEditar.disabled = false;
                btnEditar.href = `/produtos/${selecionados[0].value}/editar`;
            } else {
                btnEditar.disabled = true;
                btnEditar.href = '#';
            }
        }
    }

    if (checkboxes.length > 0) {
        checkboxes.forEach(cb => cb.addEventListener('change', atualizarBotoes));
        atualizarBotoes();
    }

    const ctx = document.getElementById('graficoCategorias');
    if (ctx) {
        const dadosGrafico = JSON.parse(ctx.dataset.grafico);
        if (dadosGrafico && dadosGrafico.length > 0) {
            new Chart(ctx, {
                type: 'pie',
                data: {
                    labels: dadosGrafico.map(d => d.categoria || 'Sem Categoria'),
                    datasets: [{
                        data: dadosGrafico.map(d => d.total),
                        backgroundColor: ['#0d6efd', '#198754', '#ffc107', '#dc3545', '#6c757d', '#0dcaf0', '#ffc107'],
                        borderColor: '#fff', borderWidth: 2, hoverOffset: 4
                    }]
                },
                options: { responsive: true, plugins: { legend: { position: 'bottom' } } }
            });
        }
    }
});