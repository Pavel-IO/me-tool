classdef StepFieldMap < metools.Step
    % STEPFIELDMAP  Field map (distortion) correction of all echoes.
    %
    %   reads   In   (bold)   all echoes
    %   writes  Out  (bold)   u<name> for every echo
    %
    %   parameters  Master (index of the master echo, default 2),
    %               FieldmapTEs (short and long echo time of the field map, ms, [5.29 7.75]),
    %               TotalReadoutTime (EPI readout time, ms, 20.8),
    %               BlipDirection (1), PhaseEncodingDir (1 = x, 2 = y, 3 = z; 2)
    %   files       <fields folder of the subject>/_phasediff.nii and _magnitude1.nii
    %   computation metools.fmri.proc.fieldmapCorrect

    properties
        Master (1,1) double {mustBeInteger, mustBePositive} = 2
        FieldmapTEs (1,2) double {mustBePositive} = [5.29 7.75]
        TotalReadoutTime (1,1) double {mustBePositive} = 20.8
        BlipDirection (1,1) double {mustBeMember(BlipDirection, [-1 1])} = 1
        PhaseEncodingDir (1,1) double {mustBeMember(PhaseEncodingDir, [1 2 3])} = 2
    end

    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end

        function msgs = check(obj, in, ~)
            msgs = {};
            if obj.Master > numel(in.In)
                msgs = {sprintf('Master echo %d requested, but the input has only %d file(s).', ...
                    obj.Master, numel(in.In))};
            end
        end

        function out = predict(~, in, ~)
            out.Out = metools.Step.addPrefix(in.In, 'u');
        end

        function files = externalFiles(~, ctx)
            files = {fullfile(ctx.FieldsDir, '_phasediff.nii'), ...
                     fullfile(ctx.FieldsDir, '_magnitude1.nii')};
        end

        function names = requiredFunctions(~)
            names = {'spm'};
        end

        function execute(obj, in, ~, ctx)
            files = in.In;
            others = files([1:obj.Master-1, obj.Master+1:end]);
            metools.fmri.proc.fieldmapCorrect(fullfile(ctx.FieldsDir, '_phasediff.nii'), ...
                fullfile(ctx.FieldsDir, '_magnitude1.nii'), files{obj.Master}, others, ...
                EchoTimes = obj.FieldmapTEs, TotalReadoutTime = obj.TotalReadoutTime, ...
                BlipDirection = obj.BlipDirection, PhaseEncodingDir = obj.PhaseEncodingDir);
        end
    end
end
