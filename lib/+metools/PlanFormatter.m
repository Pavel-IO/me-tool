classdef PlanFormatter
    % PLANFORMATTER  Text output of a compiled pipeline plan (used by Pipeline.describe).
    % The output is plain ASCII so that it renders correctly in any MATLAB console.

    methods (Static)
        function lines = format(plan)
            lines = {};
            ins = fieldnames(plan.Inputs);
            parts = cell(1, numel(ins));
            for i = 1:numel(ins)
                parts{i} = sprintf('%s (%d)', ins{i}, numel(plan.Inputs.(ins{i})));
            end
            lines{end+1} = sprintf('Pipeline ''%s''   steps: %d   inputs: %s', ...
                plan.Name, numel(plan.Steps), strjoin(parts, ', '));
            lines{end+1} = '';

            n = numel(plan.Steps);
            if n > 0
                header = {'#', 'step', 'reads', 'writes', 'freed after step'};
                cols = cell(n, 5);
                for k = 1:n
                    s = plan.Steps(k);
                    nm = s.name;
                    if ~strcmp(s.status, 'ok')
                        nm = sprintf('%s [%s]', nm, upper(s.status));
                    end

                    rl = {};
                    for r = 1:numel(s.reads)
                        rd = s.reads(r);
                        ver = plan.Versions(rd.version);
                        if ver.step == 0
                            src = 'input';
                        else
                            src = sprintf('#%d', ver.step);
                        end
                        if numel(s.reads) > 1
                            lab = sprintf('%s: %s', rd.port, rd.stream);
                        else
                            lab = rd.stream;
                        end
                        rl{end+1} = sprintf('%s <- %s', lab, src); %#ok<AGROW>
                    end

                    wl = {};
                    for w = 1:numel(s.writes)
                        wr = s.writes(w);
                        [~, fn, fe] = fileparts(wr.files{1});
                        if numel(wr.files) > 1
                            extra = sprintf(' (x%d)', numel(wr.files));
                        else
                            extra = '';
                        end
                        wl{end+1} = sprintf('%s -> %s%s', wr.stream, [fn fe], extra); %#ok<AGROW>
                    end

                    fl = {};
                    ids = plan.FreeAfter{k};
                    for i = 1:numel(ids)
                        ver = plan.Versions(ids(i));
                        fl{end+1} = sprintf('#%d.%s', ver.step, ver.stream); %#ok<AGROW>
                    end
                    if isempty(fl)
                        fl = {'-'};
                    end

                    cols{k, 1} = {sprintf('%d', k)};
                    cols{k, 2} = {nm};
                    cols{k, 3} = rl;
                    cols{k, 4} = wl;
                    cols{k, 5} = fl;
                end

                widths = cellfun(@numel, header);
                for k = 1:n
                    for c = 1:5
                        L = cols{k, c};
                        for i = 1:numel(L)
                            widths(c) = max(widths(c), numel(L{i}));
                        end
                    end
                end

                lines{end+1} = metools.PlanFormatter.rowText(header, widths);
                lines{end+1} = repmat('-', 1, sum(widths) + 2 * (numel(widths) - 1));
                for k = 1:n
                    nl = max(1, max(cellfun(@numel, cols(k, :))));
                    for i = 1:nl
                        texts = cell(1, 5);
                        for c = 1:5
                            L = cols{k, c};
                            if i <= numel(L)
                                texts{c} = L{i};
                            else
                                texts{c} = '';
                            end
                        end
                        lines{end+1} = metools.PlanFormatter.rowText(texts, widths); %#ok<AGROW>
                    end
                end
                lines{end+1} = '';

                plines = {};
                for k = 1:n
                    if ~isempty(plan.Steps(k).params)
                        plines{end+1} = sprintf('  #%d %s: %s', k, plan.Steps(k).name, plan.Steps(k).params); %#ok<AGROW>
                    end
                end
                if ~isempty(plines)
                    lines{end+1} = 'Parameters:';
                    lines = [lines, plines, {''}];
                end
            end

            if plan.RetainAll
                lines{end+1} = 'Retain: all (nothing is deleted)';
            else
                lines{end+1} = ['Retain: ' strjoin(plan.RetainList, ', ')];
            end

            for i = 1:numel(plan.Errors)
                lines{end+1} = ['ERROR: ' plan.Errors{i}]; %#ok<AGROW>
            end
            for i = 1:numel(plan.Warnings)
                lines{end+1} = ['WARNING: ' plan.Warnings{i}]; %#ok<AGROW>
            end
            if plan.Ok
                res = 'OK';
            else
                res = 'FAILED';
            end
            lines{end+1} = sprintf('Validation: %s, errors: %d, warnings: %d', ...
                res, numel(plan.Errors), numel(plan.Warnings));
        end

        function s = rowText(texts, widths)
            padded = cell(1, numel(texts));
            for c = 1:numel(texts)
                padded{c} = [texts{c}, repmat(' ', 1, widths(c) - numel(texts{c}))];
            end
            s = deblank(strjoin(padded, '  '));
        end
    end
end
