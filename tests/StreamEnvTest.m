classdef StreamEnvTest < matlab.unittest.TestCase
    methods (Test)
        function currentIsLastVersion(tc)
            env = metools.StreamEnv();
            a = env.add('bold', {'a.nii'}, '', 0, []);
            b = env.add('bold', {'b.nii'}, 'Out', 1, a);
            v = env.current('bold');
            tc.verifyEqual(v.id, b);
            tc.verifyEqual(v.files, {'b.nii'});
            tc.verifyNumElements(env.history('bold'), 2);
        end

        function ancestorsAreTransitive(tc)
            env = metools.StreamEnv();
            a = env.add('bold', {'a.nii'}, '', 0, []);
            b = env.add('bold', {'b.nii'}, 'Out', 1, a);
            c = env.add('bold_smooth', {'c.nii'}, 'Out', 2, b);
            v = env.current('bold_smooth');
            tc.verifyEqual(v.ancestors, [a b]);
            tc.verifyEqual(v.parents, b);
            tc.verifyEqual(c, 3);
        end

        function missingStream(tc)
            env = metools.StreamEnv();
            tc.verifyFalse(env.has('x'));
            tc.verifyError(@() env.current('x'), 'StreamEnv:Missing');
        end

        function badStreamName(tc)
            env = metools.StreamEnv();
            tc.verifyError(@() env.add('spatny nazev', {'a'}, '', 0, []), 'StreamEnv:BadStream');
        end

        function cloneIsIndependent(tc)
            env = metools.StreamEnv();
            env.add('bold', {'a.nii'}, '', 0, []);
            cp = env.clone();
            cp.add('bold', {'b.nii'}, 'Out', 1, 1);
            v = env.current('bold');
            tc.verifyEqual(v.files, {'a.nii'});
            tc.verifyNumElements(cp.history('bold'), 2);
        end

        function toFilesNormalizes(tc)
            tc.verifyEqual(metools.StreamEnv.toFiles('a'), {'a'});
            tc.verifyEqual(metools.StreamEnv.toFiles(["a" "b"]), {'a', 'b'});
            tc.verifyEqual(metools.StreamEnv.toFiles({'a'; 'b'}), {'a', 'b'});
            tc.verifyEmpty(metools.StreamEnv.toFiles(''));
            tc.verifyError(@() metools.StreamEnv.toFiles(5), 'StreamEnv:BadFiles');
        end
    end
end
