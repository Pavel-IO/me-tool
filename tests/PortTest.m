classdef PortTest < matlab.unittest.TestCase
    methods (Test)
        function inputDefaults(tc)
            p = metools.Port.input('bold');
            tc.verifyEqual(p.Direction, 'in');
            tc.verifyEqual(p.Stream, 'bold');
            tc.verifyEqual(p.Cardinality, 'any');
            tc.verifyFalse(p.Optional);
            tc.verifyEmpty(p.Follows);
        end

        function inputOptions(tc)
            p = metools.Port.input('rp', 'Cardinality', 'one', 'Optional', true);
            tc.verifyEqual(p.Cardinality, 'one');
            tc.verifyTrue(p.Optional);
        end

        function outputFollows(tc)
            p = metools.Port.output('', 'Follows', 'In');
            tc.verifyEqual(p.Direction, 'out');
            tc.verifyEqual(p.Follows, 'In');
        end

        function badStreamName(tc)
            tc.verifyError(@() metools.Port.input('bad name'), 'Port:BadStream');
            tc.verifyError(@() metools.Port.output(''), 'Port:BadStream');
        end

        function badOptions(tc)
            tc.verifyError(@() metools.Port.input('bold', 'Unknown', 1), 'Port:BadOptions');
            tc.verifyError(@() metools.Port.input('bold', 'Optional'), 'Port:BadOptions');
            tc.verifyError(@() metools.Port.input('bold', 'Follows', 'In'), 'Port:BadOptions');
        end
    end
end
