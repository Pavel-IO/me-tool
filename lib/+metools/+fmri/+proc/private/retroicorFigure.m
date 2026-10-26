function retroicorFigure(data, pEcg, pResp, file)
    % RETROICORFIGURE  Control figure of RETROICOR: voxels with significant cardiac (left)
    % and respiratory (right) noise, -log10(p) over the mean image, p < 0.001.
    threshold = 1e-3;
    pEcg(pEcg > threshold) = 1;
    pEcg(pEcg(:) < 1e-18) = 1e-18;
    ppEcg = imslices(-log10(pEcg), 1);
    pResp(pResp > threshold) = 1;
    pResp(pResp(:) < 1e-18) = 1e-18;
    ppResp = imslices(-log10(pResp), 1);

    bcg = mean(data, 4);
    bcg = bcg - min(bcg(:));
    BCG = imslices(bcg, 1);
    BCG = BCG / max(bcg(:));

    fig = figure('Visible', 'off');
    closeFig = onCleanup(@() close(fig));
    subplot(1, 2, 1);
    imagesc(overlayRgb(BCG, ppEcg, -log10(threshold)));
    title('Pulse');
    subplot(1, 2, 2);
    imagesc(overlayRgb(BCG, ppResp, -log10(threshold)));
    title('Breath');
    saveas(fig, file);
end
