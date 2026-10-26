classdef StepNormalize < metools.Step
    % STEPNORMALIZE  Normalization of BOLD and mean image to MNI space via the subject T1.
    %
    %   reads   In   (bold)       exactly one 4D file
    %           Mean (bold_mean)  exactly one 3D file
    %   writes  Out     (follows In)    w<name>
    %           MeanOut (follows Mean)  w<name>
    %           T1Reg   (t1_coreg)      r_t1.nii in the session folder (T1 coregistered to the mean)
    %
    % The subject T1 (<subject>/anat/_t1.nii) is skull-stripped (CAT12), coregistered to
    % the mean image and segmented; the deformation is applied to the mean and the BOLD
    % series. See metools.fmri.proc.normalizeViaT1.
    %
    %   parameters  VoxelSize        output voxel size in mm (default [2.5 2.5 2.5])
    %               CoregResolution  resolution of the resliced mean used for coregistration
    %                                (default [1 1 1])
    %   files       <subject>/anat/_t1.nii
    %   computation metools.fmri.proc.normalizeViaT1 (all intermediate files in a
    %               temporary folder; nothing is written to the anat folder)

    properties
        VoxelSize (1,3) double {mustBePositive} = [2.5 2.5 2.5]
        CoregResolution (1,3) double {mustBePositive} = [1 1 1]
    end

    methods
        function p = ports(~)
            p.In      = metools.Port.input('bold', 'Cardinality', 'one');
            p.Mean    = metools.Port.input('bold_mean', 'Cardinality', 'one');
            p.Out     = metools.Port.output('', 'Follows', 'In');
            p.MeanOut = metools.Port.output('', 'Follows', 'Mean');
            p.T1Reg   = metools.Port.output('t1_coreg');
        end

        function out = predict(~, in, ~)
            out.Out     = metools.Step.addPrefix(in.In, 'w');
            out.MeanOut = metools.Step.addPrefix(in.Mean, 'w');
            out.T1Reg   = {fullfile(fileparts(in.In{1}), 'r_t1.nii')};
        end

        function files = externalFiles(~, ctx)
            files = {fullfile(ctx.SubjectDir, 'anat', '_t1.nii')};
        end

        function names = requiredFunctions(~)
            names = {'spm', 'cat_version', 'reslice_nii'};
        end

        function execute(obj, in, out, ctx)
            metools.fmri.proc.normalizeViaT1(fullfile(ctx.SubjectDir, 'anat', '_t1.nii'), ...
                in.Mean{1}, in.In{1}, out.T1Reg{1}, ...
                VoxelSize = obj.VoxelSize, CoregResolution = obj.CoregResolution);
        end
    end
end
