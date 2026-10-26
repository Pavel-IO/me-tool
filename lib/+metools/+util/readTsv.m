function [data, header] = readTsv(file)
    % READTSV  Reads a numeric tab-separated file with a header line (see writeTsv).
    %
    %   [data, header] = metools.util.readTsv('x.tsv')
    %
    % data: rows x columns double (n/a, NaN and empty cells become NaN); header: row
    % cellstr of the column names.
    arguments
        file {mustBeTextScalar}
    end
    file = char(file);
    fid = fopen(file, 'r');
    if fid < 0
        error('readTsv:Open', 'readTsv: cannot open %s.', file);
    end
    closer = onCleanup(@() fclose(fid));
    line = fgetl(fid);
    if ~ischar(line)
        error('readTsv:Empty', 'readTsv: %s is empty.', file);
    end
    header = strsplit(strtrim(line), sprintf('\t'), 'CollapseDelimiters', false);
    n = numel(header);
    C = textscan(fid, repmat('%f', 1, n), 'Delimiter', '\t', 'TreatAsEmpty', {'n/a'}, ...
        'EmptyValue', NaN, 'CollectOutput', true, 'ReturnOnError', false);
    data = C{1};
    if isempty(data)
        data = zeros(0, n);
    end
end
