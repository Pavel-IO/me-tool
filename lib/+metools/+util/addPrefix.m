function out = addPrefix(files, prefix, suffix)
    % ADDPREFIX  File name(s) with a prefix (and optionally a suffix) added to the name.
    %
    %   metools.util.addPrefix('d:/a/bold.nii', 'r')          -> 'd:/a/rbold.nii'
    %   metools.util.addPrefix({'a.nii', 'b.nii'}, 's')       -> {'sa.nii', 'sb.nii'}
    %   metools.util.addPrefix('d:/a/bold.nii', '', '_mask')  -> 'd:/a/bold_mask.nii'
    %
    % The folder and the extension stay the same. A char/string input gives a char
    % result, a cell array gives a cell array of the same size.
    arguments
        files {mustBeText}
        prefix {mustBeTextScalar}
        suffix {mustBeTextScalar} = ''
    end
    prefix = char(prefix);
    suffix = char(suffix);
    isSingle = ischar(files) || (isstring(files) && isscalar(files));
    files = cellstr(files);
    out = cell(size(files));
    for i = 1:numel(files)
        [d, n, e] = fileparts(files{i});
        out{i} = fullfile(d, [prefix n suffix e]);
    end
    if isSingle
        out = out{1};
    end
end
