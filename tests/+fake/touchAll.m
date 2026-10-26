function touchAll(out)
    % Test helper: creates empty files for all outputs of a step.
    names = fieldnames(out);
    for i = 1:numel(names)
        files = out.(names{i});
        for j = 1:numel(files)
            d = fileparts(files{j});
            if ~isempty(d) && ~exist(d, 'dir')
                mkdir(d);
            end
            fid = fopen(files{j}, 'w');
            fclose(fid);
        end
    end
end
