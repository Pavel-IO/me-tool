function y = fcdf3(x, n1, n2)
    % FCDF3  Cumulative F distribution (no Statistics Toolbox needed). Element-wise.
    y = betainc(n1*x./(n2+n1*x), n1/2, n2/2);
end
