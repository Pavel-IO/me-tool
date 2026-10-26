classdef StepRealign < metools.Step
    % STEPREALIGN  Realigns all echoes with SPM.
    %
    % The master echo defines the mean image and the motion parameters; the other echoes
    % are resliced with the same transformation (see docs/steps/Realign.md).
    %
    %   reads   In    (bold)       all echoes
    %   writes  Out   (bold)       r<name> for every echo
    %           Mean  (bold_mean)  mean<name of the master echo>
    %           Rp    (rp)         rp_<name of the master echo>.txt
    %
    %   parameters  Master (index of the master echo, default 2), Unwarp (default false)
    %   computation metools.fmri.proc.realign
    %
    % Unwarp = true (realign & unwarp) is not implemented; the static check reports it.

    properties
        Master (1,1) double {mustBeInteger, mustBePositive} = 2
        Unwarp (1,1) logical = false
    end

    methods
        function p = ports(~)
            p.In   = metools.Port.input('bold');
            p.Out  = metools.Port.output('', 'Follows', 'In');
            p.Mean = metools.Port.output('bold_mean');
            p.Rp   = metools.Port.output('rp');
        end

        function msgs = check(obj, in, ~)
            msgs = {};
            if obj.Master > numel(in.In)
                msgs{end+1} = sprintf('Master echo %d requested, but the input has only %d file(s).', ...
                    obj.Master, numel(in.In));
            end
            if obj.Unwarp
                msgs{end+1} = 'Unwarp = true (realign & unwarp) is not implemented.';
            end
        end

        function out = predict(obj, in, ~)
            master = in.In{obj.Master};
            out.Out = metools.Step.addPrefix(in.In, 'r');
            out.Mean = metools.Step.addPrefix(in.In(obj.Master), 'mean');
            [folder, name] = fileparts(master);
            out.Rp = {fullfile(folder, ['rp_', name, '.txt'])};
        end

        function items = qc(~, ~, out, ctx)
            % Motion plot and summary values (framewise displacement after Power et al.
            % 2012 with a head radius of 50 mm; SPM rotations are in radians).
            rp = load(out.Rp{1}, '-ascii');
            trans = rp(:, 1:3);
            rot = rp(:, 4:6) * 180 / pi;
            fd = metools.fmri.proc.framewiseDisplacement(rp);

            fig = figure('Visible', 'off', 'Position', [100 100 900 650]);
            closeFig = onCleanup(@() close(fig));
            subplot(3, 1, 1); plot(trans); ylabel('mm'); title('Translation'); legend('x', 'y', 'z');
            subplot(3, 1, 2); plot(rot); ylabel('deg'); title('Rotation'); legend('pitch', 'roll', 'yaw');
            subplot(3, 1, 3); plot(fd); ylabel('mm'); xlabel('volume'); title('Framewise displacement');
            png = fullfile(ctx.QcDir, 'realign_motion.png');
            exportgraphics(fig, png);
            clear closeFig

            items = struct( ...
                'Title', {'Motion parameters', 'Max abs translation (mm)', 'Max abs rotation (deg)', ...
                          'Mean FD (mm)', 'Volumes with FD > 0.5 mm'}, ...
                'Image', {png, [], [], [], []}, ...
                'Value', {[], max(abs(trans(:))), max(abs(rot(:))), mean(fd), nnz(fd > 0.5)});
        end

        function execute(obj, in, ~, ~)
            files = in.In;
            others = files([1:obj.Master-1, obj.Master+1:end]);
            metools.fmri.proc.realign(files{obj.Master}, others, Unwarp = obj.Unwarp);
        end

        function names = requiredFunctions(~)
            names = {'spm'};
        end
    end
end
