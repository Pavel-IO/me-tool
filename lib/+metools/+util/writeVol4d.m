function writeVol4d(header, data, file)
    % WRITEVOL4D  Writes a 4D array into a NIfTI file using the SPM headers of a 4D image.
    %
    %   header  struct array from spm_vol (one element per volume), defines the geometry
    %           and data type of the output
    %   data    4D array, size(data, 4) == numel(header)
    %   file    output file name
    arguments
        header struct
        data {mustBeNumeric}
        file {mustBeTextScalar}
    end
    file = char(file);
    for i = 1:numel(header)
        header(i).fname = file;
        spm_write_vol(header(i), data(:, :, :, i));
    end
end
