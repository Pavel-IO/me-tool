function out = imslices(vol, rotate)
    % IMSLICES  Mosaic of all slices of a 3D volume (rotate = 1: transposed and flipped).
    [SY, SX, SZ] = size(vol);
    A = floor(sqrt(SZ));
    B = floor(sqrt(SZ));
    while A*B < SZ
        A = A + 1;
    end
    if nargin < 2
        rotate = 0;
    end
    rotate = min(max(rotate, 0), 1);
    if rotate == 1
        out = zeros(SX*B, SY*A);
        for i = 1:B
            for ii = 1:A
                s = (i-1)*A + ii;
                if s <= SZ
                    out((1:SX)+(i-1)*SX, (1:SY)+(ii-1)*SY) = flipud(vol(:, :, s)');
                end
            end
        end
    else
        out = zeros(SY*B, SX*A);
        for i = 1:B
            for ii = 1:A
                s = (i-1)*A + ii;
                if s <= SZ
                    out((1:SY)+(i-1)*SY, (1:SX)+(ii-1)*SX) = vol(:, :, s);
                end
            end
        end
    end
end
