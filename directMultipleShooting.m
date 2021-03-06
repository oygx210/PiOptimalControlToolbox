function [X,U,t,trajectory,J] = directMultipleShooting(lagrange,mayer,f,eqPathCon,inPathCon,eqTerCon,inTerCon,x0,tf,N,m,intMethod,varargin)
%DIRECTMULTIPLESHOOTING - solves a given optimal control problem using direct
%multiple shooting method
%   [X,U,T,J] = DIRECTMULTIPLESHOOTING(LAGRANGE,MAYER,F,EQPC,INPC,EQTC,INTC,X0,TF,N,M,INT)
%   solves a continuous time optimal control problem based on given Bolza's
%   formulation,
%
%      J* = min { int(L(x(t),u(t),t),t = 0:T) + M(x(T),T) }
%           u(.)
%
%   u*(t) = argmin { int(L(x(t),u(t),t),t = 0:T) + M(x(T),T) }
%           u(.)
%
%   s.t.           x'(t)  =  f(x(t),u(t),t)     : dynamic constraint
%           g(x(t),u(t))  =  0                  : equality path constraint
%           h(x(t),u(t)) <=  0                  : inequality path constraint
%              q(x(T),T)  =  0                  : equality terminal constraint
%              r(x(T),T) <=  0                  : inequality terminal constraint
%                   x(0)  =  x0                 : initial condition
%
%   ,which includes the following arguments.
%
%   Langrange's term (L)          : LAGRANGE - @langrange(x,u,t) -> scalar
%   Mayer's term (M)              : MAYER    - @mayer(xN,tf) -> scalar
%   dynamic system (f)            : F        - @f(x,u,t) -> dim(x)x1 column vector
%   eq. path constraint (g)       : EQPC     - @eqPathCon(x,u) -> num_eq_p column vector
%   ineq. path constraint (h)     : INPC     - @inPathCon(x,u) -> num_in_p column vector
%   eq. terminal constraint (q)   : EQTC     - @eqTerCon(xN,tf) -> num_eq_t column vector
%   ineq. terminal constraint (r) : INTC     - @inTerCon(xN,tf) -> num_in_t column vector
%   initial state (x0)            : X0       - n x 1 column vector
%   final time(T)                 : TF       - positive finite scaler or empty
%   number of sample              : N        - positive integer
%   number of control input       : m        - positive integer
%   integration method (int)      : INT      - 'euler' or 'rk4'
%
%   The function returns and plot state (x(t)) and control input (u(t))
%   trajectories, X and U respectively, with respect to a time vector T. 
%   The function also returns the minimum cost (J*) J. 
%
%   [X,U,T] = DIRECTMULTIPLESHOOTING(LAGRANGE,MAYER,F,EQPC,INPC,EQTC,INTC,X0,TF,N,M,'given',MET)
%   solves a continuous time optimal control problem based on given Bolza's
%   formulation with the given integration menthod MET.

%% Validate attributes : 

% TO DO : write the validation for each argument

%% Guess for w
n = size(x0,1);
w0 = ones(n*N+m*N,1);
freeTF = isempty(tf);

if freeTF
    w0 = [w0;10];
end

%% Formulate problem for fmincon

FUN = @(w) bolza(w,lagrange,mayer,x0,tf,N,intMethod,varargin);
A = [];
B = [];
Aeq = [];
Beq = [];
LB = [];
UB = [];
NONLCON = @(w) constraint(w,f,eqPathCon,inPathCon,eqTerCon,inTerCon,x0,tf,N,intMethod,varargin);

OPTIONS = optimoptions('fmincon','Algorithm','sqp','display','off');

%% Optimize using fmincon (or other method)

[w,J,flag] = fmincon(FUN,w0,A,B,Aeq,Beq,LB,UB,NONLCON,OPTIONS);
exitFlagfmincon(flag);

%% Obtain and visulaize state and control input trajectories

if isempty(tf)
    tf = w(end);
    u_vector = w(n*N+1:end-1);
else
    u_vector = w(n*N+1:end);
end

U = reshape(u_vector,length(u_vector)/N,N);

[X,t,~] = forwardSimulation(f,x0,U,tf,N,intMethod,'plot');

trajectory.X = piecewiseCubic(f,X,U,tf,N);
trajectory.U = piecewiseLinear(U,tf,N);


end

%% help functions

function b = bolza(w,lagrange,mayer,x0,tf,N,intMethod,varargin)
%BOLZA - calculates the total cost based on given Bolza's formulation 
%   B = BOLZA(W,L,M,X0,TF,N,INT) calculates the total cost based on given
%   guess W, Lagrange's term L, Mayer's term M, an 
%   initial states X0, a final time TF, and number of sample N with the 
%   integration method INT.
%
%   B = BOLZA(W,L,M,X0,TF,N,'given',MET) calculates the total cost based
%   on given Bolza's formulation with given integration method MET.

% Obtain guess X and U

n = size(x0,1);
if isempty(tf)
    tf = w(end);
    u_vector = w(n*N+1:end-1);
else
    u_vector = w(n*N+1:end);
end

x_vector = [x0 ; w(1:n*N)];
XGuess = reshape(x_vector,n,N+1);
UGuess = reshape(u_vector,length(u_vector)/N,N);

% Numerically evaluate Bolza's formulation using the guess

[b,~,~] = bolzaCost(lagrange,mayer,XGuess,UGuess,tf,intMethod,varargin{:});

end

function [inCon,eqCon] = constraint(w,f,eqPathCon,inPathCon,eqTerCon,inTerCon,x0,tf,N,intMethod,varargin)
%CONSTRAINT - returns evaluated inequality and equality constaints
%   [INC,EQC] = CONSTRAINT(W,F,X0,EQPC,INPC,EQTC,INTC,TF,N,INT) evaluates 
%   and forms inequality and equality constraints , INC and EQC respectively,
%   based on given guess W, dyanmic system F, an initial states X0,
%   equality path constraint EQPC, inequality path constraint INPC,
%   equality terminal constraint EQTC, inequality terminal constraint INTC,
%   final time TF, number of sample N, and integration method INT.
%
%   [INC,EQC] = CONSTRAINT(W,F,X0,EQPC,INPC,EQTC,INTC,TF,N,'given',MET) evaluates 
%   and forms inequality and equality constraints using the given
%   integration method MET for forward simulation of state trajectory.

%% Obtain guess X and U
n = size(x0,1);
freeTF = isempty(tf);
if freeTF
    tf = w(end);
    u_vector = w(n*N+1:end-1);
    dimTF = 1;
else
    u_vector = w(n*N+1:end);
    dimTF = 0;
end
x_vector = [x0 ; w(1:n*N)];
n = length(x_vector)/(N+1);
m = length(u_vector)/N;
XGuess = reshape(x_vector,n,N+1);
UGuess = reshape(u_vector,m,N);

%% Evaluate constraints

% Allocate space for equality constraint

dimEqPathCon = size(eqPathCon(XGuess(:,1),UGuess(:,1)),1);
dimEqTerCon = size(eqTerCon(XGuess(:,end),tf),1);
dimDynCon = n*N;
eqCon = zeros(dimEqPathCon*(N+1)+dimEqTerCon+dimDynCon,1);

% Allocate space for inequality constraint

dimInPathCon = size(inPathCon(XGuess(:,1),UGuess(:,1)),1);
dimInTerCon = size(inTerCon(XGuess(:,end),tf),1);
inCon = zeros(dimInPathCon*(N+1)+dimInTerCon+dimTF,1);


for i = 1:N,
    
    % Dynamic Constraint
    XSim = forwardSimulation(f,XGuess(:,i),UGuess(:,i),tf/N,1,intMethod,varargin{:});
    eqCon(dimEqPathCon*(N+1)+dimEqTerCon + n*(i-1)+1:dimEqPathCon*(N+1)+dimEqTerCon + n*i) = XGuess(:,i+1)-XSim(:,end);
    
    % Path Constraint
    eqCon(dimEqPathCon*(i-1)+1:dimEqPathCon*i,1) = eqPathCon(XGuess(:,i),UGuess(:,i));
    inCon(dimInPathCon*(i-1)+1:dimInPathCon*i,1) = inPathCon(XGuess(:,i),UGuess(:,i));
    
end
eqCon(dimEqPathCon*N+1:dimEqPathCon*(N+1),1) = eqPathCon(XGuess(:,N+1),UGuess(:,N));

% Terminal Constraint

eqCon(dimEqPathCon*(N+1)+1:dimEqPathCon*(N+1)+dimEqTerCon,1) = eqTerCon(XGuess(:,end),tf);
inCon(dimInPathCon*N+1:dimInPathCon*N+dimInTerCon,1) = inTerCon(XGuess(:,end),tf);

% Positive Time Constraint

if freeTF
    inCon(dimInPathCon*(N+1)+dimInTerCon+1,1) = -tf;
end

end