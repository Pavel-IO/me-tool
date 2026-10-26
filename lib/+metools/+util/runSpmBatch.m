function runSpmBatch(matlabbatch)
    % RUNSPMBATCH  Runs an SPM batch non-interactively (FMRI defaults, command line mode).
    spm_jobman('initcfg')
    spm('defaults', 'FMRI');
    spm_get_defaults('cmdline', true)
    spm_jobman('run', matlabbatch);
end
