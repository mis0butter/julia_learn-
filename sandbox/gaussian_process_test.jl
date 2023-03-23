using Optim 
using LinearAlgebra
using Statistics 
using Plots 
using TickTock 
using GaussianProcesses 
using Random 
using Plots 
using ProgressMeter 
using BenchmarkTools

## ============================================ ##
## ============================================ ##
# functions 

# define square distance function 
function sq_dist(a::Vector, b::Vector) 

    r = length(a) ; 
    p = length(b) 

    # iterate 
    C = zeros(r,p) 
    for i = 1:r 
        for j = 1:p 
            C[i,j] = ( a[i] - b[j] )^2 
        end 
    end 

    return C 

end 

# test function 
a = [1, 2, 3]
b = ones(5) 

C = sq_dist(b,a) 
display(C) 

## ============================================ ##
# sample from given mean and covariance 
function gauss_sample(mu::Vector, K::Matrix) 
    
    # cholesky decomposition, get lower triangular decomp 
    C = cholesky(K) ; 
    L = C.L 

    # draw random samples 
    u = randn(length(mu)) 

    # f ~ N(mu, K(x, x)) 
    f = mu + L*u 

    return f 

end 

# test function 
C = rand(3,3)
K = C + C' + 10*I 
gauss_sample(rand(3), K)

## ============================================ ##
# marginal log-likelihood for Gaussian Process 

function log_p(( σ_f, l, σ_n, x, y, μ ))
    
    # kernel function 
    k_fn(σ_f, l, xp, xq) = σ_f^2 * exp.( -1/( 2*l^2 ) * sq_dist(xp, xq) ) 

    # training kernel function 
    Ky = k_fn(σ_f, l, x, x) 
    Ky += σ_n^2 * I 

    term = zeros(2)
    # term[1] = 1/2*( y )'*inv( Ky )*( y ) 
    term[1] = 1/2*( y .- μ )'*inv( Ky )*( y .- μ ) 
    term[2] = 1/2*log(det( Ky )) 

    return sum(term)

end 

# test log-likelihood function 
N = 10
log_p(( σ_f, l, σ_n, sort(rand(N)), randn(N), zeros(N) ))


## ============================================ ##
## ============================================ ##
# create GP !!!  

Random.seed!(0) 

# true hyperparameters 
σ_f0 = 1.0 ;    σ_f = σ_f0 
l_0  = 1.0 ;    l   = l_0 
σ_n0 = 0.1 ;    σ_n = σ_n0 

# generate training data 
N = 100
x_train = sort( 2π*rand(N) ) 
N = length(x_train) 

# kernel function 
k_fn(σ_f, l, xp, xq) = σ_f^2 * exp.( -1/( 2*l^2 ) * sq_dist(xp, xq) ) 

Σ_train = k_fn( σ_f0, l_0, x_train, x_train ) 
Σ_train += σ_n0^2 * I 

# training data --> "measured" output at x_train 
# y_train = gauss_sample( 0*x_train, Σ_train ) 
y_train = sin.(x_train) .+ 0.1*randn(N) 

# scatter plot of training data 
p1 = scatter(x_train, y_train, 
    c = :black, markersize = 5, label = "training points", markershape = :cross, title = "Fit GP", legend = :outerbottom ) 


## ============================================ ##
# posterior distribution ROUND 1 
# (based on training data) 
# NO hyperparameters tuned yet 

# x  = training data  
# xs = test data 
# joint distribution 
#   [ y  ]     (    [ K(x,x)+Ïƒ_n^2*I  K(x,xs)  ] ) 
#   [ fs ] ~ N ( 0, [ K(xs,x)         K(xs,xs) ] ) 
x_test = collect( 0 : 0.1 : 2π )

# covariance from training data 
K    = k_fn(σ_f0, l_0, x_train, x_train)  
K   += σ_n0^2 * I       # add noise for positive definite 
Ks   = k_fn(σ_f0, l_0, x_train, x_test)  
Kss  = k_fn(σ_f0, l_0, x_test, x_test) 

# conditional distribution 
# mu_cond    = K(Xs,X)*inv(K(X,X))*y
# sigma_cond = K(Xs,Xs) - K(Xs,X)*inv(K(X,X))*K(X,Xs) 
# fs | (Xs, X, y) ~ N ( mu_cond, sigma_cond ); 
μ_post = Ks' * K^-1 * y_train ; 
Σ_post = Kss - (Ks' * K^-1 * Ks) ; 

# get covariances and stds 
cov_prior = diag(Kss );     std_prior = sqrt.(cov_prior); 
cov_post  = diag(Σ_post );  std_post  = sqrt.(cov_post); 

# plot fitted / predict / post data 
plot!(p1, x_test, μ_post, c = :red, label = "fitted mean (σ_0) ")
# shade covariance 
plot!(p1, x_test, μ_post .- 3*std_post, fillrange = μ_post .+ 3*std_post , fillalpha = 0.35, c = :red, label = "3σ (σ_0)")


## ============================================ ## 
# solve for hyperparameters

println("samples = ", N) 

# test reassigning function 
test_log_p(( σ_f, l, σ_n )) = log_p(( σ_f, l, σ_n, x_train, y_train, 0*y_train )) 
test_log_p(( σ_f, l, σ_n )) 

σ_0   = [σ_f0, l_0, σ_n0] * 1.1  
# σ_0    = [ σ_f, l_0, σ_n ] * 1.1 
lower = [0.0, 0.0, 0.0] 
upper = [Inf, Inf, Inf]

# result = optimize( test_log_p, lower, upper, σ_0, Fminbox(LBFGS()) ; autodiff = :forward) 
result = optimize( test_log_p, lower, upper, σ_0, Fminbox(LBFGS()) ) 
println("log_p min (LBFGS) = \n ", result3.minimizer) 

# assign optimized hyperparameters 
σ_f = result.minimizer[1] 
l   = result.minimizer[2] 
σ_n = result.minimizer[3] 


## ============================================ ##

f_test(x) = x[1]^2 + x[2]^2 
x0 = [2.0, 2.0]
lower = [0, 0] 
upper = [Inf, Inf]
od = OnceDifferentiable(f_test, x0; autodiff = :forward)
result = optimize( od, lower, upper, x0, Fminbox(LBFGS()) ) 
println("od = ", result.minimizer)

td = TwiceDifferentiable(f_test, x0; autodiff = :forward)
result = optimize( td, lower, upper, x0, Fminbox(LBFGS()) ) 
println("td = ", result.minimizer)

## ============================================ ##
# posterior distribution ROUND 2 
# (based on training data) 
# YES hyperparameters tuned 

# x  = training data  
# xs = test data 
# joint distribution 
#   [ y  ]     (    [ K(x,x)+Ïƒ_n^2*I  K(x,xs)  ] ) 
#   [ fs ] ~ N ( 0, [ K(xs,x)         K(xs,xs) ] ) 
x_test = x_test 

# covariance from training data 
K    = k_fn(σ_f, l, x_train, x_train)   
K   +=  σ_n^2 * I       # add signal noise 
Ks   = k_fn(σ_f, l, x_train, x_test)  
Kss  = k_fn(σ_f, l, x_test, x_test) 

# conditional distribution 
# mu_cond    = K(Xs,X)*inv(K(X,X))*y
# sigma_cond = K(Xs,Xs) - K(Xs,X)*inv(K(X,X))*K(X,Xs) 
# fs | (Xs, X, y) ~ N ( mu_cond, sigma_cond ); 
μ_post = Ks' * K^-1 * y_train 
Σ_post = Kss - (Ks' * K^-1 * Ks)  

# get covariances and stds 
cov_prior = diag(Kss );     std_prior = sqrt.(cov_prior) 
cov_post  = diag(Σ_post );  std_post  = sqrt.(cov_post) 

# plot fitted / predict / post data 
plot!(p1, x_test, μ_post, c = :blue, label = "fitted mean (σ_opt) ")
# shade covariance 
plot!(p1, x_test, μ_post .- 3*std_post, fillrange = μ_post .+ 3*std_post , fillalpha = 0.35, c = :blue, label = "3σ (σ_opt)")

xlabel!("x")
ylabel!("y")


## ============================================ ## 
# fit GP 

# mean and covariance 
mZero = MeanZero() ;            # zero mean function 
kern  = SE(σ_f0, l_0) ;          # squared eponential kernel (hyperparams on log scale) 
log_noise = log(σ_n0) ;              # (optional) log std dev of obs noise 

# fit GP 
gp  = GP(x_train, y_train, mZero, kern, log_noise) ; 
# optimize in a box with lower bounds [-1,-1] and upper bounds [1,1]
# optimize!(gp; kernbounds = [ [-1,-1] , [1,1] ])
p3 = plot(gp; xlabel="x", ylabel="y", title="GP vs predict_y", fmt=:png) ; 
p4 = plot(gp; xlabel="x", ylabel="y", title="GP vs predict_y (opt)", fmt=:png) ; 

# predict at test points, should be same as gp plot?? 
μ_gp, σ²_gp = predict_y( gp, x_test ) 

# optimize gp 
test = GaussianProcesses.optimize!(gp; method = LBFGS() ) 
μ_gp_opt, σ²_gp_opt = predict_y( gp, x_test ) 

# "un-optimized" 
c = 3 ; 
plot!( p3, x_test, μ_gp, c = c, label = "mean (predict_y)" )
plot!( p3, x_test, μ_gp .- 3*sqrt.(σ²_gp), fillrange = μ .+ 3*sqrt.(σ²_gp) , fillalpha = 0.15, c = c, label = "3σ (predict_y)" )

# optimized 
c = 5 ; 
plot!( p4, x_test, μ_gp_opt, c = c, label = "mean (predict_y, opt)" )
plot!( p4, x_test, μ_gp_opt .- 3*sqrt.(σ²_gp_opt), fillrange = μ .+ 3*sqrt.(σ²_gp_opt) , fillalpha = 0.15, c = c, label = "3σ (predict_y, opt)" )

# plot un-optimized and optimized 
c = 3 ; 
p5 = plot( x_test, μ_gp, c = c, label = "mean (predict_y)", title = "predict_y vs predict_y (opt)" )
plot!( p5, x_test, μ_gp .- 3*sqrt.(σ²_gp), fillrange = μ .+ 3*sqrt.(σ²_gp) , fillalpha = 0.15, c = c, label = "3σ (predict_y)" )

c = 5 ; 
plot!( p5, x_test, μ_gp_opt, c = c, label = "mean (predict_y, opt)" )
plot!( p5, x_test, μ_gp_opt .- 3*sqrt.(σ²_gp_opt), fillrange = μ .+ 3*sqrt.(σ²_gp_opt) , fillalpha = 0.15, c = c, label = "3σ (predict_y, opt)" )


p6 = plot(gp; xlabel="x", ylabel="y", title="GP vs fitted", fmt=:png) 
c = 3 ; 

# plot fitted / predict / post data 
plot!(p6, x_test, μ_post, c = 2, label = "mean (fitted) ")

# shade covariance 
plot!(p6, x_test, μ_post .- 3*std_post, fillrange = μ_post .+ 3*std_post , fillalpha = 0.1, c = 2, label = "3σ (fitted)")

# plot everything 
fig_gp_compare = plot( p3, p4, p6, p5, layout = (4,1), size = [600 1000] )


## ============================================ ##
# plot everything 

# p7 = plot(gp; xlabel="x", ylabel="y", title="Gaussian Process", fmt=:png) 

# scatter plot of training data 
p7 = scatter(x_train, y_train, 
    c = :black, markersize = 5, label = "training points", markershape = :cross, title = "Fit GP", legend = :outerbottom ) 

c = 3 ; 
# plot fitted / predict / post data 
plot!(p7, x_test, μ_post, c = :blue, label = "fitted mean (σ_opt) ")
# shade covariance 
plot!(p7, x_test, μ_post .- 3*std_post, fillrange = μ_post .+ 3*std_post , fillalpha = 0.1, c = :blue, label = "3σ (σ_opt)")

# optimized 
c = 5 ; 
plot!( p7, x_test, μ_gp_opt, c = c, label = "fitted mean (predict_y, opt)" )
plot!( p7, x_test, μ_gp_opt .- 3*sqrt.(σ²_gp_opt), fillrange = μ .+ 3*sqrt.(σ²_gp_opt) , fillalpha = 0.15, c = c, label = "3σ (predict_y, opt)" )

fig_gp_fit = plot( p1, p7, layout = (2,1), size = [ 600, 800 ] )


## ============================================ ##
# test minimizing 1-norm 

# test_fn(z) = sum(abs.(z)) .+ z'*z 
# x = -10 : 0.1 : 10 
# x = collect(x) 

# y = 0*x 
# for i = 1:length(x) 
#     y[i] = test_fn(x[i])
# end 

# result = optimize(test_fn, 0.1) 
# println("minimizer = ", result.minimizer)

# plot(x,y) 