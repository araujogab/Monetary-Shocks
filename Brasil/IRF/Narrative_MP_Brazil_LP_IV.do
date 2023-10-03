// ---------------------------------------------------- //
//  A Narrative approach to Monetary Policy in Brazil 	//
//  Date created: 1st December, 2022                    //
//  Author: Miguel Bandeira                             //
//  Insper Institute for Education and Research         //
//  Email: mbandeira [at] insper [dot] edu [dot] br     //
// ---------------------------------------------------- //

/* ---------------------------------------------------- //
// Description: File created to explore some of the     
// properties of the narratively identified series of   
// monetary shocks in Brazil from Mateus Hachul MPE 
// dissertation. This file runs the local projections 
// using the narratively identified series as an 
// *INSTRUMENT* for Delta Selic.
// ---------------------------------------------------- */


// ---------------------------------------------------- //
// 0. Housekeeping                                      //
// ---------------------------------------------------- //

clear
graph drop _all
capture log close
cd "/Users/miguelbandeira/Dropbox/Professional activities/Student Supervision/Ongoing/MPE/Mateus de Melo Hachul (Insper MPE)/Empirics/"
log using "Do files/0. log files/Narrative_MP_Brazil_LP_IV.log", replace

// Installing the ivreg2 package:
ssc install ivreg2, replace

// Installing the ranktest package:
ssc install ranktest, replace

// Installing the weakivtest package (Montiel-Olea & Pflueger,2013):
ssc install weakivtest, replace

// Installing the avar package (needed to run weakivtest command):
ssc install avar, replace



// ---------------------------------------------------- //
// 1. Importing the dataset and formatting              //
// ---------------------------------------------------- //

// Reading from Excel:
import excel "Datasets/Narrative_MP_Brazil_Dataset_with_Controls.xlsx", sheet("IPCA") firstrow allstring
quietly destring  Selic-Choque_neg, replace

// Creating date variable:
gen date = mofd(date(Data,"MDY"))
format date %tm
order date, first
label variable date "Date in SIF monthly format"
drop Data
sort date
tsset date



// ---------------------------------------------------- //
// 2. Local Projections                                 //
// ---------------------------------------------------- //

// Generating auxiliary variables for the analysis:

rename logbrlem log_brlem
label var log_brlem "Log of the BRL/EM exchange rate"
rename logfci log_fci
label var log_fci "Log of the Financial Conditions Index"
gen log_ipca = log(ipca)
label var log_ipca "Log of the Consumer Price Index"
gen log_pimsa = log(pimsa)
label var log_pimsa "Log of the Industrial Production Index (SA)"
gen log_ibcbrsa = log(ibcbrsa)
label var log_ibcbrsa "Log of the IBC-Br index (SA)"

gen D_log_ipca = D.log_ipca
label var D_log_ipca "MoM percent change in IPCA (log approx)"
gen D_log_pimsa = D.log_pimsa
label var D_log_pimsa "MoM percent change in PIMSA (log approx)"
gen D_log_brlem = D.log_brlem
label var D_log_brlem "MoM percent change BRL/EM exchange rate (log approx)"
gen D_log_fci = D.log_fci
label var D_log_fci "MoM percent change Financial Conditions index (log approx)"

gen YoY_selic = Selic - L12.Selic
label var YoY_selic "YoY change in Selic rate (in percentage points)"
gen YoY_ipca = log_ipca - L12.log_ipca
label var YoY_ipca "YoY percent change in IPCA (log approx)"
gen YoY_pimsa = log_pimsa - L12.log_pimsa
label var YoY_pimsa "YoY percent change in PIM sa (log approx)"

gen SoS_selic = Selic - L6.Selic
label var SoS_selic "SoS change in Selic rate (in percentage points)"
gen SoS_ipca = log_ipca - L6.log_ipca
label var SoS_ipca "SoS percent change in IPCA (log approx)"
gen SoS_pimsa = log_pimsa - L6.log_pimsa
label var SoS_pimsa "SoS percent change in PIM sa (log approx)"

gen QoQ_selic = Selic - L3.Selic
label var QoQ_selic "QoQ change in Selic rate (in percentage points)"
gen QoQ_ipca = log_ipca - L3.log_ipca
label var QoQ_ipca "QoQ percent change in IPCA (log approx)"
gen QoQ_pimsa = log_pimsa - L3.log_pimsa
label var QoQ_pimsa "QoQ percent change in PIM sa (log approx)"



// Choice of the maximum horizon for the local projections and organizing to save the results:
local H = 36
generate h = _n - 1
replace  h = . if h > `H'
label var h "Horizon (in months)"

// Generate a variable to be the LHS of the local projections (replace later):
generate LP_lhs = .

// Main Local Projections Loop starts here:
// Outer loop over variables
// Inner loop over horizons of the local projections

foreach var of varlist log_ipca log_pimsa log_fci log_brlem {
	
	// Defining the controls (if any) to use in the local projection:
	// For example use 1-12 lags of variables W and Z as controls use
	// global controls "L(1/12).W L(1/12).Z"
	// For no controls simply create an empty list: global controls ""
	// Tying some things:
	//global controls "L.YoY_selic L.YoY_ipca L.YoY_pimsa L.SoS_selic L.SoS_ipca L.SoS_pimsa L.QoQ_selic L.QoQ_ipca L.QoQ_pimsa"
	//global controls "L(1/3).Selic_d L(1/3).D_log_ipca L(1/3).D_log_pimsa"
	local controls_lag = 2
	global controls "L(1/`controls_lag').Selic L(1/`controls_lag').log_ipca L(1/`controls_lag').log_pimsa L(1/`controls_lag').log_brlem L(1/`controls_lag').log_fci"
	//global controls "L(1/`controls_lag').Selic_d L(1/`controls_lag').D_log_ipca L(1/`controls_lag').D_log_pimsa L(1/`controls_lag').D_log_brlem L(1/`controls_lag').D_log_fci"'
	
	// Generating the variables to store the results depending on the case:
	gen LP_b_lhs_`var' = .              // To store the betas (IRFs) from Local Projections
	gen LP_se_lhs_`var' = .             // To store the standard errors from Local Projections
	gen LP_F_eff_lhs_`var' =.           // To store the first stage effective F stat for the Montiel-Olea & Pflueger weak IV test
	gen LP_F_crit_tau5_lhs_`var' =.     // To store the first stage F critical value for tau = 5%
	gen LP_F_crit_tau10_lhs_`var' =.    // To store the first stage F critical value for tau = 10%
	gen LP_F_crit_tau20_lhs_`var' =.    // To store the first stage F critical value for tau = 20%
	gen LP_F_crit_tau30_lhs_`var' =.    // To store the first stage F critical value for tau = 30%
	
	// Adding labels to first stage variables:
	label var LP_F_eff_lhs_`var' "First-stage effective F statistic"
	label var LP_F_crit_tau5_lhs_`var' "TSLS critical value for tau = 5%" 
	label var LP_F_crit_tau10_lhs_`var' "TSLS critical value for tau = 10%" 
	label var LP_F_crit_tau20_lhs_`var' "TSLS critical value for tau = 20%" 
	label var LP_F_crit_tau30_lhs_`var' "TSLS critical value for tau = 30%" 
	
	// Starting the regressions for each horizon
	forvalues h = 0(1)`H' {
	
	// Creating the variable to be on the LHS of Local projections:
	replace LP_lhs = F`h'.`var' - L.`var'
		
		// Defining Newey-West truncation and running the LP regression:
		local nw_lag_truncation = `h'+1
		
		// Running the Local Projection here:
		// Note: either ivreg2 or ivregress should given the exact same results (using only one):
		ivreg2 LP_lhs (Selic = Choque) $controls, first robust bw(`nw_lag_truncation')
		//ivregress gmm LP_lhs (Selic = Choque) $controls, first wmatrix(hac nw `nw_lag_truncation')
		
		// Saving the cofficient of interest and respective standard errors
		replace LP_b_lhs_`var' = _b[Selic] if h == `h'
		replace LP_se_lhs_`var' = _se[Selic] if h == `h'
	
		// Running the test for Montiel-Olea and Pflueger (2013):
		weakivtest, level(0.05)
		
		// Saving the effective F stat and CVs for different taus:
		replace LP_F_eff_lhs_`var' = r(F_eff) if h == `h'
		replace LP_F_crit_tau5_lhs_`var' = r(c_TSLS_5) if h == `h'
		replace LP_F_crit_tau10_lhs_`var' = r(c_TSLS_10) if h == `h'
		replace LP_F_crit_tau20_lhs_`var' = r(c_TSLS_20) if h == `h'
		replace LP_F_crit_tau30_lhs_`var' = r(c_TSLS_30) if h == `h'
		
		// Saving these values in a local variable for plotting first stage Fs:
		local x_pos   = floor(0.9*`H')
		local y_tau5  = r(c_TSLS_5)  +1
		local y_tau10 = r(c_TSLS_10) +1
		local y_tau20 = r(c_TSLS_20) +1 
		local y_tau30 = r(c_TSLS_30) +1
		local y_max   = 10*ceil((`y_tau5'-1)/10)
		// Note the 1 extra is to make it better in the plotting
	
	}
	
	// Plotting and saving the IRF for this particular variable:
	
	// Generating auxiliary variables for plots:
	gen x_axis = 0 if h!=.
	gen ci_ub  = LP_b_lhs_`var' + 1.96*LP_se_lhs_`var' if h!=.
	gen ci_lb  = LP_b_lhs_`var' - 1.96*LP_se_lhs_`var' if h!=.
	
	// Plotting the IRF:
	if `var' == log_ipca {
	// Change the delimiting to make graph coding easier	
	#delimit ;
	twoway 
	(line x_axis h, lcolor(black) lwidth(medthin)) 
	(rarea ci_ub ci_lb h, fcolor(gs10%50) lcolor(black%50) lwidth(vvthin)) 
	(line LP_b_lhs_`var' h, lcolor(black) lwidth(medthick))
	, 
	ytitle(Cumulated change in log IPCA from t - 1 to t + h) 
	ylabel(, grid glwidth(vthin) glcolor(black) glpattern(dash) nogmin nogmax) 
	xlabel(0(3)`H', grid glwidth(vthin) glcolor(black) glpattern(dash) nogmin nogmax) 
	legend(off) 
	graphregion(fcolor(white) ifcolor(white)) 
	plotregion(lcolor(black) lpattern(solid) lwidth(thin) margin(zero)) 
	name(IRF_`var')
	;
	#delimit cr
	
	// Plotting the first stage F statistics (only once since it is identical):
	// Change the delimiting to make graph coding easier	
	#delimit ;
	twoway 
	(line LP_F_eff_lhs_log_ipca h, lcolor(black) lwidth(medthick) lpattern(solid)) 
	(line LP_F_crit_tau5_lhs_log_ipca h, lcolor(gs8) lwidth(medthick) lpattern(dash)) 
	(line LP_F_crit_tau10_lhs_log_ipca h, lcolor(gs8) lwidth(medthick) lpattern(dash)) 
	(line LP_F_crit_tau20_lhs_log_ipca h, lcolor(gs8) lwidth(medthick) lpattern(dash)) 
	(line LP_F_crit_tau30_lhs_log_ipca h, lcolor(gs8) lwidth(medthick) lpattern(dash))
	, 
	text(`y_tau5'  `x_pos' "tau = 5%", place(c) size(medsmall))
	text(`y_tau10' `x_pos' "tau = 10%", place(c) size(medsmall))
	text(`y_tau20' `x_pos' "tau = 20%", place(c) size(medsmall))
	text(`y_tau30' `x_pos' "tau = 30%", place(c) size(medsmall))
	ytitle(First stage effective F statistics)
	ylabel(0(5)`y_max', nogrid glwidth(vthin) glcolor(black) glpattern(dash) nogmin nogmax)
	xlabel(0(3)`H', nogrid glwidth(vthin) glcolor(black) glpattern(dash) nogmin nogmax) 
	legend(off)
	graphregion(fcolor(white) ifcolor(white)) 
	plotregion(lcolor(black) lpattern(solid) lwidth(thin) margin(zero)) 
	name(First_stage_F)
	;
	#delimit cr
	
	}
	else if `var' == log_pimsa {
	// Change the delimiting to make graph coding easier
	#delimit ;
	twoway (line x_axis h, lcolor(black) lwidth(medthin))
	(rarea ci_ub ci_lb h, fcolor(gs10%50) lcolor(black%50) lwidth(vvthin)) 
	(line LP_b_lhs_`var' h, lcolor(black) lwidth(medthick))
	, 
	ytitle(Cumulated change in log PIM from t - 1 to t + h) 
	ylabel(, grid glwidth(vthin) glcolor(black) glpattern(dash) nogmin nogmax) 
	xlabel(0(3)`H', grid glwidth(vthin) glcolor(black) glpattern(dash) nogmin nogmax) 
	legend(off) 
	graphregion(fcolor(white) ifcolor(white)) 
	plotregion(lcolor(black) lpattern(solid) lwidth(thin) margin(zero)) 
	name(IRF_`var')
	;
	#delimit cr
	}
	else if `var' == log_fci {
	// Change the delimiting to make graph coding easier
	#delimit ;
	twoway (line x_axis h, lcolor(black) lwidth(medthin))
	(rarea ci_ub ci_lb h, fcolor(gs10%50) lcolor(black%50) lwidth(vvthin)) 
	(line LP_b_lhs_`var' h, lcolor(black) lwidth(medthick))
	, 
	ytitle(Cumulated change in log FCI from t - 1 to t + h) 
	ylabel(, grid glwidth(vthin) glcolor(black) glpattern(dash) nogmin nogmax) 
	xlabel(0(3)`H', grid glwidth(vthin) glcolor(black) glpattern(dash) nogmin nogmax) 
	legend(off) 
	graphregion(fcolor(white) ifcolor(white)) 
	plotregion(lcolor(black) lpattern(solid) lwidth(thin) margin(zero)) 
	name(IRF_`var')
	;
	#delimit cr
	}
	else if `var' == log_brlem {
	// Change the delimiting to make graph coding easier
	#delimit ;
	twoway (line x_axis h, lcolor(black) lwidth(medthin))
	(rarea ci_ub ci_lb h, fcolor(gs10%50) lcolor(black%50) lwidth(vvthin)) 
	(line LP_b_lhs_`var' h, lcolor(black) lwidth(medthick))
	, 
	ytitle(Cumulated change in log ER from t - 1 to t + h) 
	ylabel(, grid glwidth(vthin) glcolor(black) glpattern(dash) nogmin nogmax) 
	xlabel(0(3)`H', grid glwidth(vthin) glcolor(black) glpattern(dash) nogmin nogmax) 
	legend(off) 
	graphregion(fcolor(white) ifcolor(white)) 
	plotregion(lcolor(black) lpattern(solid) lwidth(thin) margin(zero)) 
	name(IRF_`var')
	;
	#delimit cr
	}
	
	// Exporting the graph:
	graph export "./Graphs/Narrative/Narrative_LP_IV_IRF_`var'.pdf", name(IRF_`var') as(pdf) replace
	graph export "./Graphs/Narrative/Narrative_First_stage_F.pdf", name(First_stage_F) as(pdf) replace
	
	// Cleaning the auxiliary variables:
	drop x_axis ci_ub ci_lb

}


// Exporting an excel spreadsheet with all the results plotted:
drop LP_lhs
export excel h LP* using "Results/xlsx/Narrative_MP_Brazil_LP_IV_Results.xlsx", firstrow(variables) replace

// Exporting a dta file with all the results plotted:
keep h LP*
save "Results/dta/Narrative_MP_Brazil_LP_IV_Results.xlsx", replace


// ---------------------------------------------------- //
// X. Ending                                            //
// ---------------------------------------------------- //
log close 


