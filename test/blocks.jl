@testset "SimpleBlock" begin
    using SequenceJacobians.RBC
    firm, household, mkt_clearing = RBC.firm, RBC.household, RBC.mkt_clearing
    ins = [:K, :L, :Z, :α, :δ]
    outs = (:r, :w, :Y)
    b = block(firm, [lag(:K), :L, :Z, :α, :δ], outs)
    @test b isa SimpleBlock
    @test inputs(b) === (ins...,)
    @test ssinputs(b) == Set(ins)
    @test outputs(b) === (outs...,)
    @test b(10.0, 1.0, 1.0, 0.3, 0.05) === NamedTuple{outs}(firm(10.0, 1.0, 1.0, 0.3, 0.05))

    @test_throws ArgumentError block(firm, (), outs)
    @test_throws ArgumentError block(firm, ins, ())
    @test_throws ArgumentError block(firm, ins, outs, ssins=:n)
    @test_throws ArgumentError block(firm, ins, ins)

    ins = [:K, :K, :L, :w, :eis, :frisch, :φ, :δ]
    outs = [:C, :I]
    b = block(household, [:K, lag(:K), :L, :w, :eis, :frisch, :φ, :δ], outs)
    @test inputs(b) == (ins...,)

    ins = [:r, :r, :C, :C, :Y, :I, :K, :K, :L, :w, :eis, :β]
    outs = [:goods_mkt, :euler, :walras]
    b = block(mkt_clearing,
        [:r, lead(:r), :C, lead(:C), :Y, :I, :K, lag(:K), :L, :w, :eis, :β], outs)
    @test inputs(b) == (ins...,)

    bfirm, bhh, bmkt, bss = rbcblocks()
    varvals = (K=2, L=1, w=1, eis=1, frisch=1, φ=0.9, δ=0.025)
    varvals = steadystate!(bhh, varvals)
    @test varvals[:C] ≈ 1.1111111111111112
    @test varvals[:I] ≈ 0.05

    @test jacobian(bhh, Val(1), 5, varvals) ≈ [0, 1]
    @test jacobian(bhh, Val(2), 5, varvals) ≈ [0, -0.975]
    @test jacobian(bhh, Val(8), 5, varvals) ≈ [0, 2]
end

@testset "HetBlock" begin
    using SequenceJacobians.KrusellSmith
    ins = (:r, :w, :β, :eis)
    outs = (:A, :C)
    b = kshhblock(0, 200, 500, 0.966, 0.5, 7)
    @test inputs(b) === ins
    @test outputs(b) === outs
    @test !hascache(b)
    @test outlength(b) == 2

    varvals = (r=0.01, w=0.89, β=0.98, eis=1)
    varvals = steadystate!(b, varvals)
    # Compare results with original Python package
    a = b.ha.a
    @test all(a[1:4,1] .== 0)
    @test all(a[1:3,3] .== 0)
    @test a[5:8,1] ≈ [1.66414395e-3, 3.43258549e-3, 5.22507103e-3, 7.04179415e-3] atol=1e-7
    @test a[1:4,7] ≈ [0.90054142, 0.90383955, 0.90718218, 0.9105699] atol=1e-7
    @test a[end-3:end,7] ≈ [190.6133331, 193.1797762, 195.78086653, 198.41707144] atol=1e-6
    D = b.ha.D
    @test D[1:3,1] ≈ [1.41373523e-2, 4.08282500e-5, 3.83039718e-5] atol=1e-8
    @test D[1:3,4] ≈ [1.42736359e-2, 1.82294210e-2, 2.57256128e-2] atol=1e-8
    @test D[1:3,7] ≈ [3.38553410e-8, 9.33874325e-8, 1.32361967e-7] atol=1e-8
    @test varvals[:C] ≈ 0.9112915134243005 atol=1e-7
    @test varvals[:A] ≈ 2.1291511229699926 atol=1e-7

    # Feed in steady-state values from Python package for comparing results
    varvals = (r=0.01, w=0.89, β=0.981952788061795, eis=1)
    b = kshhblock(0, 200, 500, 0.966, 0.5, 7)
    @test_throws ErrorException jacobian(b, Val(1), 5, varvals)
    varvals = steadystate!(b, varvals)
    # Check jacobian for effect on impact
    j = jacobian(b, Val(1), 1, varvals)
    dv = j.df[:,:,1]
    # Derivatives from Python package are based on a fixed epsilon
    # Need to specify twosided=True for better accuracy
    @test dv[1:3,1] ≈ [4.32936187, 4.20445547, 4.08329971] atol=1e-7
    @test dv[498:500,7] ≈ [0.06198027, 0.06095875, 0.05994965] atol=1e-7
    dev = j.dEVs[1]
    @test dev[1:3,1] ≈ [4.18343962, 4.06543792, 3.95090303] atol=1e-7
    @test dev[498:500,7] ≈ [0.06166387, 0.06064379, 0.05963622] atol=1e-7

    dD = j.dDs[1][:,:,1]
    @test dD[1:3,1] ≈ [-1.22588821e-4, -2.04934264e-5, -5.59833386e-5] atol=1e-9
    @test j.dYs[1] ≈ [3.047070890160419 0.09578625552963749] atol=1e-7

    # Check jacobian for 1-period ahead anticipation effect
    j = jacobian(b, Val(1), 2, varvals)
    dv = j.df[:,:,1]
    @test dv[1:3,1] ≈ [0, 0, 0]
    @test dv[1:3,5] ≈ [0.89735076, 0.89719971, 0.89689996] atol=1e-7
    @test dv[498:500,7,1] ≈ [0.06039384, 0.05940069, 0.05841955] atol=1e-7
    dev = j.dEVs[1]
    @test dev[1:3,1] ≈ [1.01749209e-4, 1.02397696e-4, 1.02879336e-4] atol=1e-10
    dD = j.dDs[1][:,:,2]
    @test dD[1:3,1] ≈ [-2.45911683e-3,  6.72083192e-4, -3.48413238e-5] atol=1e-10
    @test j.dYs[1][2,:] ≈ [0.6818556801588316, -0.6818556801588341] atol=1e-6

    j = jacobian(b, Val(1), 3, varvals)
    @test j.Es[1][1:3,1,1] ≈ [-29.52928609, -29.52928582, -29.52928554] atol=1e-7
    @test j.Es[1][498:500,7,2] ≈ [163.33189788, 165.91565888, 168.53432082] atol=1e-7
    @test j.Es[2][1:3,1,1] ≈ [-1.39279428, -1.38938866, -1.38593711] atol=1e-7
    @test j.Es[2][498:500,7,2] ≈ [3.89850409, 3.9474403, 3.99701225] atol=1e-7

    j = jacobian(b, Val(1), 5, varvals)
    @test j.Js[1][1][1,:] ≈ [3.04707089, 0.68185568, 0.64125217, 0.60439044, 0.57061299] atol=1e-6
    @test j.Js[1][1][5,:] ≈ [2.79839241, 3.42915491, 4.05731394, 4.68424741, 5.31162232] atol=1e-6
    @test j.Js[1][2][1,:] ≈ [0.09578626, -0.68185568, -0.64125217, -0.60439044, -0.57061299] atol=1e-6
    @test j.Js[1][2][5,:] ≈ [0.08926242, 0.12116544, 0.15313027, 0.18541724, 0.21771175] atol=1e-6
end

@testset "CombinedBlock" begin
    using SequenceJacobians: TwoAsset as ta
    ins0 = (:pip, :mc, :r, :Y, :κp, :mup, lead(:r), lead(:pip), lead(:Y))
    outs = :pip
    bpricing = block(ta.pricing, ins0, :nkpc)
    mpricing = model(bpricing)
    sspricing = SteadyState(mpricing, [:mc=>0.985, :r=>0.0125, :Y=>1, :κp=>0.1, :mup=>1.015228426395939], :pip=>0.1, :nkpc=>0)
    ins = (:mc, :r, :Y, :κp, :mup)
    @test_throws ArgumentError block(sspricing, ins, outs, :nkpc)
    @test_throws ArgumentError block(sspricing, ins0, outs, :nkpc, solver=Roots_Default)
    b = block(sspricing, ins, outs, :nkpc, solver=Roots_Default)
    @test inputs(b) == ins
    @test invars(b) == ins
    @test ssinputs(b) == Set(ins)
    @test outputs(b) == (:pip,)
    @test !hascache(b)
    @test outlength(b) == 1
    @test outlength(b, 1) == 1
    @test model(b) === mpricing
    varvals = getvarvals(sspricing)
    steadystate!(b, varvals)
    @test getval(b.ss, :pip) ≈ 0 atol=1e-8
    @test getval(b.ss, :nkpc) ≈ 0 atol=1e-8

    # Compare results with original Python package
    J = jacobian(b, 3, varvals)
    @test all(isapprox.(J.Gs[:κp][:pip], 0, atol=1e-8))
    Jmc = [0.1 0.09876543 0.09754611;
           0   0.1        0.09876543;
           0   0          0.1        ]
    @test J.Gs[:mc][:pip] ≈ Jmc atol=1e-8
    Jmup = [0.0970225 0.09582469 0.09464167;
            0         0.0970225  0.09582469;
            0         0          0.0970225  ]
    @test J.Gs[:mup][:pip] ≈ Jmup atol=1e-8
    @test all(isapprox.(J.Gs[:Y][:pip], 0, atol=1e-8))
    @test all(isapprox.(J.Gs[:r][:pip], 0, atol=1e-8))

    ins0 = (:p, :div, :r, lead(:r), lead(:div), lead(:p))
    outs = :p
    barbitrage = block(ta.arbitrage, ins0, :equity)
    ins = (:div, :r)
    b = block(barbitrage, ins, outs, :equity, [:div=>0.14, :r=>0.0125], :p=>10, :equity=>0,
        solver=Brent(), ssargs=(:x0=>(5,15),))
    varvals = steadystate!(b, getvarvals(b.ss))
    @test getval(b.ss, :p) ≈ 11.2 atol=1e-8

    # Compare results with original Python package
    J = jacobian(b, 3, varvals)
    Jdiv = [0 0.98765432 0.97546106;
            0 0          0.98765432;
            0 0          0          ]
    @test J.Gs[:div][:p] ≈ Jdiv atol=1e-8
    Jr = [0 -11.0617284 -10.92516385;
          0 0           -11.0617284;
          0 0           0            ]
    @test J.Gs[:r][:p] ≈ Jr atol=1e-8

    blabor = block(ta.labor, (:Y, :w, :K, :Z, :α, lag(:K)), (:N, :mc))
    ins0 = [:Q, :K, :r, :N, :mc, :Z, :δ, :εI, :α, lead(:r), lead(:K), lead(:Q), lead(:mc),
        lag(:K), lead(:Z), lead(:N)]
    binvest = block(ta.investment, ins0, [:inv, :val])
    calis = [:Y, :w, :Z, :α, :r, :δ, :εI]
    b = block([blabor, binvest], [:Y, :w, :Z, :r], [:Q, :K], [:inv, :val],
        calis.=>[1.0, 0.66, 0.4677898145312322, 0.3299492385786802, 0.0125, 0.02, 4],
        [:Q=>2, :K=>11], [:inv, :val].=>0.0, solver=GSL_Hybrids)
    varvals = steadystate!(b, getvarvals(b.ss))
    @test varvals[:Q] ≈ 1 atol=1e-8
    @test varvals[:K] ≈ 10 atol=1e-8

    # Compare results with original Python package
    J = jacobian(b, 3, varvals)
    Jyk = [0 0.03789632 0.03714605;
           0 0.03761037 0.07490055;
           0 0.03746678 0.0746146  ]
    @test J.Gs[:Y][:K] ≈ Jyk atol=1e-8
    Jrq = [0 -0.97663311 -0.95729755;
           0 0.00736934  -0.97297837;
           0 0.00370042   0.00736934 ]
    @test J.Gs[:r][:Q] ≈ Jrq atol=1e-8
end

@testset "SolvedBlock" begin
    using SequenceJacobians: TwoAsset as ta
    b = ta.pricing_block()
    varvals = steadystate!(b, getvarvals(b.ss))
    J = jacobian(b, 3, varvals)
    bj = block(b, J)
    @test inputs(bj) == inputs(b)
    @test invars(bj) == invars(b)
    @test ssinputs(bj) == ssinputs(b)
    @test outputs(bj) == outputs(b)
    @test hascache(bj) == hascache(b)
    @test outlength(bj) == outlength(b)
    @test outlength(bj, 1) == outlength(b, 1)

    @test_throws ErrorException steadystate!(bj, varvals)
    @test jacbyinput(bj) == false
    @test jacobian(bj, 3, varvals) === J
    @test_throws ErrorException jacobian(bj, 5, varvals)
end

const tassvals = (β = 0.9762739008880043, eis = 0.5, χ0 = 0.25, χ1 = 6.416419594214106,
    χ2 = 2, w = 0.66, ρ_z = 0.966, σ_z = 0.92, Y = 1.0, Z = 0.4677898145312322,
    α = 0.3299492385786802, r = 0.0125, δ = 0.02, εI = 4, κp = 0.1,
    mup = 1.015228426395939, rstar = 0.0125, φ = 1.5, G = 0.2, Bg = 2.8, tot_wealth = 14,
    Bh = 1.04, ω = 0.005, κw = 0.1, muw = 1.1, vφ = 1.71347594405051,
    frisch = 1.0, Q = 1.0, K = 10.0, N = 1.0, mc = 0.985, inv = 0.0, val = 0.0,
    pip = 0.0, nkpc = 0.0, piw = 0.0, i = 0.012499999999379603, ψp = 0.0,
    I = 0.2, div = 0.14, p = 11.2, equity = 0.0, pshare = 0.864197530864201,
    rb = 0.0075, ra = 0.0125, fisher = 0.0, tax = 0.3560606060606061,
    A = 12.96, B = 1.04, C = 0.5820937276337769, UCE = 4.434878914013147,
    CHI = 0.012706305302404831, wnkpc = 0.0, asset_mkt = 0.0, wealth = 14.0, goods_mkt = 0.0)

compare(a::NT, b::NT, tol::Real) where NT<:NamedTuple =
    all(k->isapprox(a[k], b[k], atol=tol), keys(a))

@testset "TwoAsset" begin
    using SequenceJacobians: TwoAsset as ta
    @testset "SimpleBlock" begin
        bdividend = ta.dividend_block()
        @test compare(steadystate!(bdividend, tassvals), tassvals, 1e-8)
        btaylor = ta.taylor_block()
        @test compare(steadystate!(btaylor, tassvals), tassvals, 1e-8)
        bfiscal = ta.fiscal_block()
        @test compare(steadystate!(bfiscal, tassvals), tassvals, 1e-8)
        bfinance = ta.finance_block()
        @test compare(steadystate!(bfinance, tassvals), tassvals, 1e-8)
        bwage = ta.wage_block()
        @test compare(steadystate!(bwage, tassvals), tassvals, 1e-8)
        bunion = ta.union_block()
        @test compare(steadystate!(bunion, tassvals), tassvals, 1e-8)
        bmkt_clearing = ta.mkt_clearing_block()
        @test compare(steadystate!(bmkt_clearing, tassvals), tassvals, 1e-7)
        bshare_value = ta.share_value_block()
        @test compare(steadystate!(bshare_value, tassvals), tassvals, 1e-8)
        bpartial_ss = ta.partial_ss_block()
        @test compare(steadystate!(bpartial_ss, tassvals), tassvals, 1e-7)
        bunion_ss = ta.union_ss_block()
        @test compare(steadystate!(bunion_ss, tassvals), tassvals, 1e-8)
    end
    @testset "CombinedBlock" begin
        bpricing = ta.pricing_block()
        @test compare(steadystate!(bpricing, tassvals), tassvals, 1e-8)
        barbitrage = ta.arbitrage_block()
        @test compare(steadystate!(barbitrage, tassvals), tassvals, 1e-8)
        bproduction = ta.production_block()
        @test compare(steadystate!(bproduction, tassvals), tassvals, 1e-8)
    end
end
