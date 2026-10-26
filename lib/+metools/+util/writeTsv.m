function writeTsv(file, header, data, options)
    % WRITETSV  Writes a numeric matrix with a header line as a tab-separated text file.
    %
    %   metools.util.writeTsv('x.tsv', {'a', 'b'}, [1 2; 3 NaN])
    %
    % One column per header name. Missing values (NaN) are written as n/a (BIDS
    % convention); numbers with Precision significant digits (default 8). Tabs and line
    % breaks in the names are replaced by spaces. Read back with metools.util.readTsv; in
    % Python with pandas.read_csv(file, sep='\t') (n/a becomes NaN automatically).
    arguments
        file {mustBeTextScalar}
        header
        data {mustBeNumericOrLogical}
        options.Precision (1,1) double {mustBeInteger, mustBePositive} = 8
    end
    header = cellstr(header);
    header = regexprep(header(:)', '[\t\r\n]', ' ');
    if size(data, 2) ~= numel(header)
        error('writeTsv:BadSize', 'writeTsv: %d column names, but the data have %d columns.', ...
            numel(header), size(data, 2));
    end
    file = char(file);
    metools.util.ensureFolder(fileparts(file));
    fid = fopen(file, 'w');
    if fid < 0
        error('writeTsv:Open', 'writeTsv: cannot open %s for writing.', file);
    end
    closer = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', strjoin(header, sprintf('\t')));
    if isempty(data)
        return
    end
    data = double(data);
    num = sprintf('%%.%dg', options.Precision);
    fmt = [strjoin(repmat({num}, 1, size(data, 2)), '\t') '\n'];
    block = 1000;
    for r = 1:block:size(data, 1)
        rows = r:min(r + block - 1, size(data, 1));
        s = sprintf(fmt, data(rows, :)');
        fwrite(fid, strrep(s, 'NaN', 'n/a'), 'char');
    end
end
