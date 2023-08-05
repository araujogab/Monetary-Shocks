*add renormalization after two-step procedures

clear all 
set more off //desativa a mensagem de "more" para permitir a visualização completa dos resultados do Stata
local maturity 2
* latest date
local year 2020 
local month 12
local monthname Dec
local MAR2020 0  //whether to include March 2020

*cd   "/Users/buchunya/Documents/Projects/BRW2019/BRW_Update201907"   //change to local folder

clear 
import excel using "DGS`maturity'.xls", firstrow case(lower) //2 year treasury rate from st louis Fed. This is different from the yield curve data since the yield curve data are estimated based on off-the-run data.
rena observation_date date

gen year= year(date)
gen month=month(date)
gen day=day(date) 
gen mdate = ym(year,month) // cria variavel mdate com o formato AAAA-MM
drop if mdate>m(2019m9)

gen dgs_d= dgs`maturity'[_n]-dgs`maturity'[_n-1] // toma a diferença da série
keep if mdate>=m(1994m1)


cap: tsset mdate,m  //define mdate como uma variável de série temporal ´cap' é usado para suprimir mensagens de erro caso a variável já esteja definida como serie temporal

drop year month day //remove as variáveis year, month e day, pois não são mais necessárias

save temp.dta, replace


******************************************************************************
clear 
local MAR2020 0
import excel using "FOMCdate.xlsx", firstrow case(lower) //FOMC dates, q denote wheter it is a FOMC announcement date or one week before that, in the appendix we show that identification through heteroskedasticity can be implemented with IVs 
gen year= year(date)
gen month=month(date)
gen day=day(date)
gen mdate = ym(year,month) // cria data formatada yyyym
if `MAR2020' == 0 {
drop if mdate == m(2020m3) //March 15 is Sunday
}

drop year month day mdate
merge 1:1 date using temp.dta,force

drop if _merge!=3
drop _merge

replace q=0 if q==.
save temp.dta, replace



******************************************************************************
clear
local MAR2020 0
insheet using feds200628.csv, names clear
gen a = date(date, "YMD")
cap: rena date a
destring sveny*, replace force 
keep a sveny*
destring sveny*, force replace // Converte todas as variáveis que começam com "sveny" em formato numérico

gen year =year(a)
gen month=month(a)
gen day=day(a)
destring year month day, force replace
gen date=mdy( month, day, year)
format date %td
gen mdate=ym(year,month)
cap: tsset mdate,m // Define a variável "mdate" como a variável de tempo (time series)
drop a year month day
order date mdate sveny*
sort date

local list "01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30" //cria lista para todas as maturities das tresuries
foreach num in  `list' { 
gen sveny`num'_d=sveny`num'[_n]-sveny`num'[_n-1] if mdate>=m(1994m1) //toma a diferença da série para cada maturity
}
keep date sveny*_d 

merge 1:1 date using  temp.dta, force // considera apenas os dados das FOMCs meeting e uma semana após
drop if _merge!=3
drop _merge

*** alignment
** step 1  // estimação via 2sls para a variavel dependente de cada maturity utilizando os valores da variação na tx da treasury 2y uma semana apos o FOMC
gen iv=dgs_d if q==1
replace iv=-dgs_d if q==0

foreach num in `list' {
ivregress 2sls  sveny`num'_d  (dgs_d=iv) 
gen beta`num'_d=_b[dgs_d]
}
gen aligned_dgs_d=.

** step 2
keep if q==1

gen t=_n
qui sum t
local maxt = r(max)
dis `maxt'


local shift 30
forvalues i = 1/`maxt'{  
preserve
 keep if t== `i'
 
xpose, clear varname
gen name = substr(_varname,1,4)
gen lastname = substr(_varname,-1,1)
keep if name=="sven" | name=="beta"
drop if lastname != "d"
drop name lastname

gen sveny_d=.
foreach b in `list' {
replace sveny_d=v1 if _varname=="sveny`b'_d"
}


gen beta_d=.
gen beta_d_temp=.
foreach b in `list'{
replace beta_d_temp=v1 if _varname=="beta`b'_d"
}
replace beta_d=beta_d_temp[_n+`shift'] 

drop beta_d_temp
capture {
reg sveny_d  beta_d  if sveny_d!=.  //regride a variavel dependente no beta estimado anteriormente para achar o et_aligned
local p=_b[beta_d] // salva o et_aligned estimado
} 
restore 
replace aligned_dgs_d=`p' if t==`i'
}


keep aligned_dgs_d date dgs_d mdate
*renormalization
rena aligned_dgs_d _newshock
qui reg dgs_d _newshock
gen scalar_normal = _b[_newshock]
gen newshock1 = _newshock*scalar_normal
drop _newshock scalar_normal
reg dgs_d newshock1


rena newshock1 BRW_daily
if `MAR2020' == 1 {
replace date = date - 1 if mdate == m(2020m3)   //March 15 is Sunday
}
save BRWupdated_meeting, replace

*summarized by month
collapse (sum ) BRW dgs_d, by(mdate)

tsset mdate,m
tsline BRW 
graph export "BRW_`year'`monthname'.png", replace

save BRWupdated.dta,replace




******************************************************************************
* Generating monthly date variable extending back to 1994
clear all
qui set obs 1
qui gen date = ym(1994,1)
qui local diff	=	ym(`year',`month')-ym(1994,1)
forvalues jj=1(1)`diff' {
	qui local new = `jj'+1
	qui set obs `new'
	qui replace date = ym(1994,1)+`jj' if date==.
}

format date %tm
rena date mdate
qui merge 1:1 mdate using BRWupdated.dta
drop _merge


replace BRW_daily = 0 if BRW_daily == .
save BRWupdated.dta,replace

twoway bar BRW_daily mdate if mdate>=m(1994m1) ,  title("New Shock Series And Unconventional Monetary Policy",size (medium)) xtitle("") ytitle("") legend(off) color(gray)  xline(590 610 633,lc(navy))   xline(620 629, lc(orange)) xline(669, lc(blue))  saving(unconventioanl.gph, replace) 
graph export "Unconventioanl.png", replace







