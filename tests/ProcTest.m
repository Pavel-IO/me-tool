classdef ProcTest < matlab.unittest.TestCase
    % Tests of the stand-alone functions in metools.util and metools.fmri.proc.
    % Tests that need SPM are skipped when SPM is not on the path.

    properties
        Root
    end

    methods (TestMethodSetup)
        function makeRoot(tc)
            fx = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.Root = fx.Folder;
        end
    end

    methods (Access = private)
        function needSpm(tc)
            tc.assumeNotEmpty(which('spm'), 'SPM is not on the path.');
        end

        function f = write4d(tc, name, data)
            % Writes a small 4D NIfTI file with SPM.
            f = fullfile(tc.Root, name);
            n = size(data, 4);
            V = repmat(struct('fname', f, 'dim', [size(data, 1) size(data, 2) size(data, 3)], ...
                'dt', [spm_type('float32') 0], 'mat', eye(4), 'pinfo', [1 0 0]', 'n', [1 1], ...
                'descrip', 'test'), n, 1);
            for i = 1:n
                V(i).n = [i 1];
                spm_write_vol(V(i), data(:, :, :, i));
            end
        end

        function f = write3d(tc, name, data, mat)
            % Writes a 3D NIfTI file (float32) with the given voxel-to-mm matrix.
            f = fullfile(tc.Root, name);
            V = struct('fname', f, 'dim', size(data, 1:3), 'dt', [spm_type('float32') 0], ...
                'mat', mat, 'pinfo', [1 0 0]', 'n', [1 1], 'descrip', 'test');
            spm_write_vol(V, data);
        end
    end

    methods (Static, Access = private)
        function [cleaned, X] = legacyRegression(vol, motion, signals, tr)
            % The nuisance regression of METools 0.1 (clearFmriData), on an array.
            [Xx, Yy, Zz, k] = size(vol);
            n = fix(2*(k*tr)/128 + 1);
            X0 = spm_dctmtx(k, n);
            invX0Tetc = pinv(X0'*X0)*X0';
            mrf = motion;
            for in = 1:size(mrf, 2)
                bet = invX0Tetc*mrf(1:k, in);
                mrf(1:k, in) = mrf(1:k, in) - X0*bet;
            end
            X = mrf;
            fwd = metools.fmri.proc.framewiseDisplacement(mrf(:, 1:6), RotationUnits = 'none', Detrend = true);
            bet = invX0Tetc*fwd;
            X = [X fwd - X0*bet];
            for in = 1:size(signals, 2)
                signal = signals(1:k, in);
                bet = invX0Tetc*signal;
                X = [X signal - X0*bet]; %#ok<AGROW>
            end
            X = [X X0];
            invXTetc = pinv(X'*X)*X';
            cleaned = vol;
            for ix = 1:Xx
                for iy = 1:Yy
                    for iz = 1:Zz
                        s = squeeze(vol(ix, iy, iz, :));
                        bet = invXTetc*s;
                        cleaned(ix, iy, iz, :) = s - X*bet + X(:, end-n+1)*bet(end-n+1);
                    end
                end
            end
        end
    end

    methods (Test)
        function addPrefixKeepsType(tc)
            tc.verifyEqual(metools.util.addPrefix(fullfile('d', 'b.nii'), 'r'), fullfile('d', 'rb.nii'));
            tc.verifyEqual(metools.util.addPrefix("b.nii", 's'), 'sb.nii');
            tc.verifyEqual(metools.util.addPrefix({'a.nii', 'b.nii'}, 'w'), {'wa.nii', 'wb.nii'});
            tc.verifyEqual(metools.util.addPrefix('b.nii', '', '_mask'), 'b_mask.nii');
            tc.verifyEqual(metools.Step.addPrefix({'a.nii'}, 'x'), {'xa.nii'});
        end

        function framewiseDisplacementUnits(tc)
            rp = zeros(3, 6);
            rp(2, 1) = 1;            % 1 mm translation
            rp(3, 4) = 0.01;         % 0.01 rad rotation
            fd = metools.fmri.proc.framewiseDisplacement(rp);
            tc.verifyEqual(fd, [0; 1; 1 + 0.5], 'AbsTol', 1e-12);
            fd = metools.fmri.proc.framewiseDisplacement(rp, RotationUnits = 'none');
            tc.verifyEqual(fd, [0; 1; 1.01], 'AbsTol', 1e-12);
            fd = metools.fmri.proc.framewiseDisplacement(rp, RotationUnits = 'degrees', Radius = 10);
            tc.verifyEqual(fd(3), 1 + 0.01*2*10*pi/360, 'AbsTol', 1e-12);
            tc.verifySize(metools.fmri.proc.framewiseDisplacement(rp, Detrend = true), [3 1]);
        end

        function readMarkersParsesFile(tc)
            f = fullfile(tc.Root, 'markers.csv');
            lines = {'# Sampling interval is 2ms', 'Type, Description, Position', 'Mk, R, 900', ...
                'Mk, R128, 1000', 'Mk, R, 1100', 'Mk, Resp, 1200', 'Mk, R128, 1500', 'Mk, R, 1600', ...
                'Mk, R128, 2000', 'Mk, Sync On, 2100'};
            fid = fopen(f, 'w');
            fprintf(fid, '%s\n', lines{:});
            fclose(fid);
            m = metools.fmri.proc.readMarkers(f);
            tc.verifyEqual(m.r128, [0 1 2], 'AbsTol', 1e-12);
            tc.verifyEqual(m.ECG, [0.2 1.2], 'AbsTol', 1e-12);
            tc.verifyEqual(m.resp, 0.4, 'AbsTol', 1e-12);
            tc.verifyEqual(m.debug_ECG_lines, [5 8]);
            tc.verifyError(@() metools.fmri.proc.readMarkers(fullfile(tc.Root, 'none.csv')), 'readMarkers:NotFound');
        end

        function readMarkersRejectsUnknownMarker(tc)
            f = fullfile(tc.Root, 'bad.csv');
            fid = fopen(f, 'w');
            fprintf(fid, '%s\n', '# Sampling interval is 2ms', 'header', 'Mk, R128, 1000', 'Mk, What, 1100');
            fclose(fid);
            tc.verifyError(@() metools.fmri.proc.readMarkers(f), 'readMarkers:UnknownMarker');
        end

        function readSliceTiming(tc)
            f = fullfile(tc.Root, 'acq.json');
            fid = fopen(f, 'w');
            fprintf(fid, '{"SliceTiming": [0, 0.4, 0, 0.4]}');
            fclose(fid);
            tc.verifyEqual(metools.fmri.proc.readSliceTiming(f), [0; 0.4; 0; 0.4]);
            fid = fopen(f, 'w');
            fprintf(fid, '{"TR": 1}');
            fclose(fid);
            tc.verifyError(@() metools.fmri.proc.readSliceTiming(f), 'readSliceTiming:Missing');
        end

        function tempFolderIsRemoved(tc)
            [d, cleanup] = metools.util.tempFolder();
            fid = fopen(fullfile(d, 'x.txt'), 'w');
            fclose(fid);
            tc.verifyTrue(isfolder(d));
            clear cleanup
            tc.verifyFalse(isfolder(d));
        end

        function volumesAndWriting(tc)
            tc.needSpm();
            data = rand(4, 5, 3, 6);
            f = tc.write4d('a.nii', data);
            tc.verifyEqual(metools.util.scanCount(f), 6);
            vols = metools.util.volumeList(f);
            tc.verifySize(vols, [6 1]);
            tc.verifyEqual(vols{2}, [f ',2']);
            out = fullfile(tc.Root, 'b.nii');
            metools.util.writeVol4d(spm_vol(f), 2 * data, out);
            tc.verifyEqual(spm_read_vols(spm_vol(out)), double(single(2 * data)), 'AbsTol', 1e-5);
        end

        function smoothWritesOnlyTheOutput(tc)
            tc.needSpm();
            f = tc.write4d('a.nii', rand(8, 8, 8, 3));
            out = fullfile(tc.Root, 'sa.nii');
            metools.fmri.proc.smooth(f, out, 4);
            tc.verifyEqual(metools.util.scanCount(out), 3);
            listing = dir(fullfile(tc.Root, '*.nii'));
            tc.verifyEqual(sort({listing.name}), {'a.nii', 'sa.nii'});
        end

        function retroicorModelRemovesCardiacSignal(tc)
            tc.needSpm();
            tr = 1;
            t = 120;
            % own random stream: SPM may switch the global generator to the legacy mode
            % in which rng() fails
            rs = RandStream('mt19937ar', 'Seed', 1);
            % irregular beats and breaths, so that the phase regressors have full rank
            markers.r128 = (0:t-1) * tr;
            markers.ECG = cumsum([0, 0.8 + 0.2*rand(rs, 1, 200)]);
            markers.resp = cumsum([0, 3.5 + rand(rs, 1, 60)]);
            times = (0:t-1) * tr;
            phase = zeros(1, t);
            for i = 1:t
                k = find(markers.ECG <= times(i), 1, 'last');
                phase(i) = (times(i) - markers.ECG(k)) / (markers.ECG(k+1) - markers.ECG(k));
            end
            data = zeros(2, 2, 2, t);
            data(1, 1, 1, :) = 100 + 5 * cos(2*pi*phase);
            data(2, 2, 2, :) = 100;
            corrected = metools.fmri.proc.retroicorModel(data, tr, markers, [0; 0]);
            tc.verifyLessThan(std(squeeze(corrected(1, 1, 1, :))), 0.5);
            tc.verifyEqual(mean(squeeze(corrected(2, 2, 2, :))), 100, 'AbsTol', 1e-6);
            [~, pEcg] = metools.fmri.proc.retroicorModel(data, tr, markers, [0; 0], ComputeStats = true);
            tc.verifySize(pEcg, [2 2 2]);
            tc.verifyLessThan(pEcg(1, 1, 1), 1e-3);
        end

        function nuisanceRegressionKeepsMean(tc)
            tc.needSpm();
            t = 50;
            noise = randn(t, 1);
            data = zeros(2, 2, 1, t);
            for i = 1:2
                for j = 1:2
                    data(i, j, 1, :) = 50 + 3 * noise;
                end
            end
            f = tc.write4d('a.nii', data);
            out = fullfile(tc.Root, 'qa.nii');
            motion = randn(t, 24);
            X = metools.fmri.proc.nuisanceRegression(f, out, motion, noise, 2);
            cleaned = spm_read_vols(spm_vol(out));
            tc.verifyEqual(squeeze(mean(cleaned, 4)), squeeze(mean(data, 4)), 'AbsTol', 1e-3);
            tc.verifyLessThan(max(std(reshape(cleaned, [], t), 0, 2)), 1e-3);
            tc.verifyEqual(size(X, 2), 24 + 1 + 1 + fix(2*(t*2)/128 + 1));
        end

        function tsvRoundTrip(tc)
            f = fullfile(tc.Root, 'x.tsv');
            data = [1 2.5; NaN -3e-7; 4 1e6];
            metools.util.writeTsv(f, {'a', 'b c'}, data);
            txt = fileread(f);
            tc.verifySubstring(txt, sprintf('a\tb c\n'));
            tc.verifySubstring(txt, 'n/a');
            [d, h] = metools.util.readTsv(f);
            tc.verifyEqual(h, {'a', 'b c'});
            tc.verifyEqual(d, data, 'RelTol', 1e-7);
            tc.verifyError(@() metools.util.writeTsv(f, {'a'}, data), 'writeTsv:BadSize');
            metools.util.writeTsv(f, {'a', 'b'}, zeros(0, 2));
            [d, h] = metools.util.readTsv(f);
            tc.verifySize(d, [0 2]);
            tc.verifyEqual(h, {'a', 'b'});
        end

        function motionRegressorModels(tc)
            rp = [0 0 0 0 0 0; 1 2 3 0.1 0.2 0.3; 2 2 2 0 0 0];
            [R, names] = metools.fmri.proc.motionRegressors(rp, 24);
            tc.verifySize(R, [3 24]);
            tc.verifyEqual(R(:, 7:12), [zeros(1, 6); diff(rp)]);
            tc.verifyEqual(R(:, 13:18), rp.^2);
            tc.verifyEqual(names{1}, 'trans_x');
            tc.verifyEqual(names{24}, 'rot_z_derivative1_power2');
            tc.verifySize(metools.fmri.proc.motionRegressors(rp, 12), [3 12]);
            tc.verifyEqual(metools.fmri.proc.motionRegressors(rp, 6), rp);
            [R0, n0] = metools.fmri.proc.motionRegressors(rp, 0);
            tc.verifySize(R0, [3 0]);
            tc.verifyEmpty(n0);
        end

        function outlierScansNeighbours(tc)
            fd = [0 0.1 0.9 0.1 0 0 0.6 0]';
            tc.verifyEqual(find(metools.fmri.proc.outlierScans(fd, 0.5))', [3 7]);
            out = metools.fmri.proc.outlierScans(fd, 0.5, Before = 1, After = 2);
            tc.verifyEqual(find(out)', [2 3 4 5 6 7 8]);
        end

        function connectivityMatrixValues(tc)
            t = (1:50)';
            a = sin(t/3);
            ts = [a, 2*a + 1, -a, ones(50, 1), NaN(50, 1)];
            r = metools.fmri.proc.connectivityMatrix(ts);
            tc.verifyEqual(r(1, 2), 1, 'AbsTol', 1e-12);
            tc.verifyEqual(r(1, 3), -1, 'AbsTol', 1e-12);
            tc.verifyTrue(all(isnan(diag(r))));
            tc.verifyTrue(all(isnan(r(:, 4))) && all(isnan(r(:, 5))));
            ts = [a, a + 0.5*cos(t/2)];
            z = metools.fmri.proc.connectivityMatrix(ts, Measure = 'fisherz');
            r = metools.fmri.proc.connectivityMatrix(ts);
            tc.verifyEqual(z(1, 2), atanh(r(1, 2)), 'AbsTol', 1e-12);
        end

        function dctFilterBasisBands(tc)
            tc.needSpm();
            n = 200;
            tr = 1;
            [X0, names] = metools.fmri.proc.dctFilterBasis(n, tr, [1/128 Inf]);
            tc.verifyEqual(size(X0, 2), fix(2*(n*tr)/128 + 1));       % SPM high-pass
            tc.verifyEqual(names{1}, 'dct_constant');
            tc.verifyEqual(size(metools.fmri.proc.dctFilterBasis(n, tr, [0 Inf]), 2), 1);
            [X0, names] = metools.fmri.proc.dctFilterBasis(n, tr, [0.01 0.1]);
            % low-pass: columns j with (j-1)/(2*n*tr) > 0.1, i.e. j = 42..200
            nHp = fix(2*n*tr*0.01 + 1);
            tc.verifyEqual(size(X0, 2), nHp + (n - 42 + 1));
            tc.verifyEqual(names{end}, sprintf('dct_lp%03d', n - 41));
            tc.verifyError(@() metools.fmri.proc.dctFilterBasis(n, tr, [0.1 0.01]), 'dctFilterBasis:BadBand');
        end

        function bandPassRegression(tc)
            tc.needSpm();
            n = 200;
            tr = 1;
            t = (0:n-1)';
            % cosines of the DCT basis: frequency (j-1)/(2*n*tr), here 0.03 and 0.3 Hz
            slow = cos(pi*(2*t + 1)*12/(2*n));
            fast = cos(pi*(2*t + 1)*120/(2*n));
            data = zeros(3, 1, 1, n);
            data(1, 1, 1, :) = 100 + slow + fast;
            data(2, 1, 1, :) = 50 + fast;
            data(3, 1, 1, :) = 80 + slow;
            f = tc.write4d('a.nii', data);

            % band-pass alone: the slow cosine and the mean stay, the fast one goes
            [X, names, c, lp] = metools.fmri.proc.nuisanceDesign(zeros(n, 0), {}, tr, Band = [0.01 0.1]);
            tc.verifyEqual(names{c}, 'dct_constant');
            tc.verifyTrue(all(startsWith(names(lp), 'dct_lp')));
            tc.verifyEqual(numel(lp), n - 41);
            out = fullfile(tc.Root, 'qa.nii');
            metools.fmri.proc.regressOut(f, out, X, Keep = c);
            y = squeeze(spm_read_vols(spm_vol(out)));
            tc.verifyEqual(y(1, :)', 100 + slow, 'AbsTol', 1e-3);
            tc.verifyEqual(y(2, :)', 50*ones(n, 1), 'AbsTol', 1e-3);
            tc.verifyEqual(y(3, :)', 80 + slow, 'AbsTol', 1e-3);

            % with censored scans (inside and at the start): the pass-band signal is not
            % pulled towards the mean around them (it was, with spike regressors)
            censored = false(n, 1);
            censored([1 2 17 18 120]) = true;
            out = fullfile(tc.Root, 'qb.nii');
            metools.fmri.proc.regressOut(f, out, X, Keep = c, Censored = censored, LowPass = lp);
            y = squeeze(spm_read_vols(spm_vol(out)));
            tc.verifyEqual(y(3, 3:end)', 80 + slow(3:end), 'AbsTol', 0.05);   % spikes: error ~1
            tc.verifyEqual(mean(y(2, :)), 50, 'AbsTol', 0.05);
        end

        function censoringWithoutLowPassEqualsSpikes(tc)
            % Without a low-pass, the uncensored scans get the same values as with one spike
            % regressor per censored scan; the censored scans are interpolated.
            tc.needSpm();
            rs = RandStream('mt19937ar', 'Seed', 11);
            n = 60;
            R = randn(rs, n, 3);
            data = 100 + randn(rs, 2, 2, 1, n);
            f = tc.write4d('a.nii', data);
            [X, ~, c, lp] = metools.fmri.proc.nuisanceDesign(R, {}, 2, Band = [1/128 Inf]);
            tc.verifyEmpty(lp);
            censored = false(n, 1);
            censored([10 11 40]) = true;
            out = fullfile(tc.Root, 'qa.nii');
            metools.fmri.proc.regressOut(f, out, X, Keep = c, Censored = censored);
            S = double((1:n)' == [10 11 40]);
            ref = fullfile(tc.Root, 'qs.nii');
            metools.fmri.proc.regressOut(f, ref, [S X], Keep = c + 3);
            y = reshape(spm_read_vols(spm_vol(out)), [], n);
            yr = reshape(spm_read_vols(spm_vol(ref)), [], n);
            tc.verifyEqual(y(:, ~censored), yr(:, ~censored), 'AbsTol', 1e-4);
            t = (1:n)';
            tc.verifyEqual(y(:, 40), interp1(t(~censored), y(:, ~censored)', 40, 'pchip')', 'AbsTol', 1e-4);
            tc.verifyError(@() metools.fmri.proc.regressOut(f, out, X, Censored = true(n, 1)), ...
                'regressOut:TooFewScans');
        end

        function nuisanceRegressionMatchesLegacy(tc)
            tc.needSpm();
            rs = RandStream('mt19937ar', 'Seed', 3);
            k = 80;
            tr = 0.851;
            rp = cumsum(0.05 * randn(rs, k, 6));
            rp(:, 4:6) = rp(:, 4:6) / 50;
            motion = metools.fmri.proc.motionRegressors(rp, 24);
            signals = randn(rs, k, 2);
            data = 100 + randn(rs, 3, 3, 2, k) + reshape(rp(:, 1), 1, 1, 1, k);
            f = tc.write4d('a.nii', data);
            vol = spm_read_vols(spm_vol(f));
            [expected, Xold] = ProcTest.legacyRegression(vol, motion, signals, tr);
            out = fullfile(tc.Root, 'qa.nii');
            X = metools.fmri.proc.nuisanceRegression(f, out, motion, signals, tr);
            tc.verifyEqual(X, Xold, 'AbsTol', 1e-9);
            tc.verifyEqual(spm_read_vols(spm_vol(out)), double(single(expected)), 'AbsTol', 1e-4);
        end

        function compCorFindsComponents(tc)
            tc.needSpm();
            rs = RandStream('mt19937ar', 'Seed', 5);
            n = 100;
            t = (0:n-1)';
            s1 = sin(2*pi*0.05*t);
            s2 = cos(2*pi*0.11*t);
            data = zeros(4, 4, 2, n);
            for i = 1:4
                for j = 1:4
                    data(i, j, 1, :) = 100 + rand(rs)*s1 + rand(rs)*s2 + 0.01*randn(rs, n, 1);
                end
            end
            f = tc.write4d('a.nii', data);
            ref = tc.write3d('mean.nii', mean(data, 4), eye(4));
            mask = zeros(4, 4, 2);
            mask(:, :, 1) = 1;
            m = tc.write3d('mask.nii', mask, eye(4));
            [c, e] = metools.fmri.proc.compCor(f, ref, m, 1, 3);
            tc.verifySize(c, [n 3]);
            tc.verifyGreaterThan(sum(e(1:2)), 0.99);
            % compCor detrends and high-pass filters the voxels, so compare with s1 treated alike
            s1f = metools.fmri.proc.highpassDetrend(s1, 1);
            b = c(:, 1:2) \ s1f;
            tc.verifyLessThan(norm(c(:, 1:2)*b - s1f) / norm(s1f), 0.05);
        end

        function parcellateResamplesAtlasToData(tc)
            tc.needSpm();
            n = 20;
            rs = RandStream('mt19937ar', 'Seed', 7);
            % data: 8 x 8 x 4 voxels of 1 mm (centres at 1..8 mm); every voxel has its own
            % offset and the signal of its half of the brain (x <= 4 or x > 4)
            f1 = randn(rs, n, 1);
            f2 = randn(rs, n, 1);
            offset = rand(rs, 8, 8, 4);
            data = zeros(8, 8, 4, n);
            for i = 1:8
                if i <= 4, sig = f1; else, sig = f2; end
                data(i, :, :, :) = repmat(offset(i, :, :), [1 1 1 n]) + reshape(sig, 1, 1, 1, n);
            end
            f = tc.write4d('a.nii', data);
            % atlas: 4 x 4 x 2 voxels of 2 mm, voxel a covers data voxels 2a-1 and 2a;
            % labels 1 (x <= 4 mm) and 3 (x > 4 mm) in the lower slab, background above
            mat = [2 0 0 -0.5; 0 2 0 -0.5; 0 0 2 -0.5; 0 0 0 1];
            A = zeros(4, 4, 2);
            A(1:2, :, 1) = 1;
            A(3:4, :, 1) = 3;
            atlas = tc.write3d('atlas.nii', A, mat);
            lab = fullfile(tc.Root, 'labels.txt');
            fid = fopen(lab, 'w');
            fprintf(fid, '# comment\n1 Left 255 0 0 0\n3\tRight\n');
            fclose(fid);

            res = metools.fmri.proc.parcellate(f, atlas, Labels = lab);
            tc.verifyEqual(res.labels, [1; 3]);
            tc.verifyEqual(res.names, {'Left'; 'Right'});
            tc.verifyEqual(res.gridVoxels, [64; 64]);
            tc.verifyEqual(res.coverage, [1; 1], 'AbsTol', 1e-12);
            m1 = mean(reshape(offset(1:4, :, 1:2), [], 1));
            m3 = mean(reshape(offset(5:8, :, 1:2), [], 1));
            tc.verifyEqual(res.timeseries, [f1 + m1, f2 + m3], 'AbsTol', 1e-4);
            tc.verifyEqual(res.centroid(1, :), [2.5 4.5 1.5], 'AbsTol', 1e-12);

            % brain mask covering only the lower data slice: half of every ROI
            M = zeros(8, 8, 4);
            M(:, :, 1) = 1;
            mask = tc.write3d('mask.nii', M, eye(4));
            res = metools.fmri.proc.parcellate(f, atlas, Mask = mask, MinCoverage = 0.6);
            tc.verifyEqual(res.coverage, [0.5; 0.5], 'AbsTol', 1e-12);
            tc.verifyEqual(res.included, [false; false]);
            tc.verifyTrue(all(isnan(res.timeseries(:))));

            % voxel template: every atlas voxel > 0 is a ROI of 2 x 2 x 2 data voxels
            res = metools.fmri.proc.parcellate(f, atlas, AtlasType = 'voxels', Summary = 'mean');
            tc.verifyEqual(numel(res.labels), 16);
            tc.verifyEqual(res.gridVoxels, 8*ones(16, 1));
            tc.verifyEqual(res.timeseries(:, 1), f1 + mean(reshape(offset(1:2, 1:2, 1:2), [], 1)), 'AbsTol', 1e-4);
            tc.verifyEqual(res.names{1}, '2_2_2');

            % eigen: the ROI signal is the shared time course (zero mean, same sign)
            res = metools.fmri.proc.parcellate(f, atlas, Summary = 'eigen');
            r = corrcoef(res.timeseries(:, 1), f1);
            tc.verifyGreaterThan(r(1, 2), 0.999);
        end
    end
end
