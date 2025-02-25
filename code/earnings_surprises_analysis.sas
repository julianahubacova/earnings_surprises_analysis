/***************************/
/*	JULIANA HUBACOVA       */
/*	261199618              */
/*	ACCT626: Assignment 2  */
/*	Feb 11th, 2025          */
/***************************/

/****************/
/* Question 1   */
/****************/

/* Step 1: Sample construction and data preparation */
proc sql;
create table funda_data_clean as
select gvkey, cusip, datadate, fyear, ib, csho, fic
from comp.funda
where 1971 <= fyear <= 2017 
      and indfmt = 'INDL' 
      and datafmt = 'STD' 
      and popsrc = 'D' 
      and consol = 'C'
      and fic = 'USA';
quit;

data funda_data_clean;
    set funda_data_clean;
    by gvkey fyear;
    eps = ib / csho;
    lag_eps = lag(eps);
    if first.gvkey then lag_eps = .;
    change_eps = eps - lag_eps;
    if change_eps > 0 then news = 'Good';
    else if change_eps < 0 then news = 'Bad';
    else delete;
run;

/* Step 2: Extract CRSP daily stock returns */
proc sql;
create table crsp_daily as
select permno, date, ret
from crsp.dsf
where 1970 <= year(date) <= 2018;
quit;

/* Step 3: Merge Compustat and CRSP */
proc sql;
create table merged as
select a.gvkey, a.datadate, a.fyear, a.news, b.permno, b.date, b.ret
from funda_data_clean a
inner join crsp.ccmxpf_lnkhist c on a.gvkey=c.gvkey
inner join crsp_daily b on b.permno=c.lpermno and 
  intnx('year',a.datadate,-1,'s') <= b.date <= intnx('year',a.datadate,1,'s')
where c.linktype in ('LC','LU') and c.linkprim in ('P','C')
  and b.ret is not null;
quit;

/* Step 4: Calculate abnormal returns */
proc sql;
create table market_ret as
select date, mean(ret) as mkt_ret
from merged
group by date;
quit;

proc sql;
create table merged_ar as
select a.*, b.mkt_ret, 
  a.ret - b.mkt_ret as ab_ret
from merged a
left join market_ret b on a.date = b.date;
quit;

/* Step 5: Align returns around earnings announcement date */
data merged_ar;
set merged_ar;
event_day = intck('day', datadate, date);
if -360 <= event_day <= 360;
run;

/* Step 6: Calculate cumulative abnormal returns */
proc sort data=merged_ar;
by news event_day;
run;

proc means data=merged_ar noprint;
by news event_day;
var ab_ret;
output out=car mean=mean_ar;
run;

data car;
set car;
by news;
retain cum_ar 0;
cum_ar + mean_ar;
if first.news then cum_ar = mean_ar;
run;

/* Step 7: Generate the figure */
proc sgplot data=car;
series x=event_day y=cum_ar / group=news;
refline 0 / axis=x lineattrs=(color=gray pattern=dash);
xaxis label="Days relative to earnings announcement";
yaxis label="Cumulative abnormal return";
title "Market Reaction to Earnings News (1971-2017)";
run;


/****************/
/* Question 2   */
/****************/

/**********************************************************************************/
/* 1. Filter the dataset to keep data from 2022-2024 with FPI = 1 & 2             */
/**********************************************************************************/

data ibes;
	set ibes.DET_EPSUS;
	where 2022 <= year(ANNDATS_ACT) <= 2024 and FPI in ("1", "2");  
run;	*Filtered dataset;

/**********************************************************************************/
/* 2. Keep only the latest forecast by each analyst for each firm-year            */
/**********************************************************************************/

proc sort data=ibes nodupkey;
	by CUSIP FPEDATS ANALYS descending ANNDATS;  
run; 

proc sort data=ibes nodupkey;
	by CUSIP FPEDATS ANALYS;  
run; *Unique analyst forecasts per firm-year;

/**********************************************************************************/
/* 3. Compute the consensus forecast for each firm-fiscal year                    */
/**********************************************************************************/

proc means data=ibes nway noprint mean n;
    class CUSIP FPEDATS;
    var VALUE;
    id actual ANNDATS_ACT;
    output out=ibes1 mean=consensus n=Num_fcst;
run;

/**********************************************************************************/
/* 4. Compute the earnings surprise (sur_earn)                                    */
/**********************************************************************************/

data ibes_surprise;
    set ibes1;
    sur_earn = (actual - consensus) / abs(actual);
    if missing(sur_earn) then delete;  * Remove missing values;
run;

/**********************************************************************************/
/* 5. Winsorize the earnings surprise variable                                    */
/**********************************************************************************/

filename m3 url 'https://gist.githubusercontent.com/JoostImpink/497d4852c49d26f164f5/raw/11efba42a13f24f67b5f037e884f4960560a2166/winsorize.sas';
%include m3;

%winsor(dsetin=ibes_surprise, dsetout=ibes_surprise_winsor, vars=sur_earn, type=Trim, pctl=10 90);

/**********************************************************************************/
/* 6. Plot the distribution of earnings surprises                                 */
/**********************************************************************************/

ods graphics on;
proc univariate data=ibes_surprise_winsor noprint;
   histogram sur_earn / normal midpoints=-0.6 to 0.9 by 0.02;
   inset n = 'Number of obs' / position=nw;
   title "Distribution of Surprise Earnings";
run;

/* Relationships between the actual earnings and the consensus analyst forecasts. */
ods graphics on;
proc sgplot data=ibes_surprise_winsor;
    scatter x=consensus y=actual / markerattrs=(symbol=circlefilled size=8);
    reg x=consensus y=actual / lineattrs=(color=red pattern=dash) legendlabel="Trend Line";
    xaxis label="Consensus Analyst Forecasts";
    yaxis label="Actual Earnings";
    title "Relationship Between Actual Earnings and Consensus Forecasts";
run;



**********************************************************************;

proc sql;
	create table temp as 
	select unique year(statpers) as year, count(distinct cusip) as nfirm, count(cusip) as n, mean(meanrec) as meanrec
	from ibes.recdsum
	where year(statpers)>2022
	group by year(statpers);
quit;

* temporary table;
data temp;
	set ibes.recdsum;
	where year(statpers)>2022;
	year=year(statpers);
	q=qtr(statpers);
run;

* For every year and quarter, we show the frequency, mean and median;
proc means data=temp nway noprint;
	class year q;
	var meanrec;
	output out = final (rename=(_freq_=freq) drop = _type_) mean=meanrec median=meanrec;
run;
