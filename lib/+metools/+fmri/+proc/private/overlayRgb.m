function rgb = overlayRgb(background, positive, threshold)
    % OVERLAYRGB  Grey background with a red-yellow overlay of the values above threshold.
    % (Simplified port of rgb_obraz for positive maps only.)
    maxPos = max(positive(:));
    rgb = repmat(background, [1 1 3]);
    if maxPos > 0
        [ny, nx] = size(positive);
        for ii = 1:nx
            for i = 1:ny
                if positive(i, ii) > threshold
                    rgb(i, ii, 1) = 1;
                    rgb(i, ii, 2) = (positive(i, ii) - threshold) / (maxPos - threshold);
                    rgb(i, ii, 3) = 0;
                end
            end
        end
    end
end
