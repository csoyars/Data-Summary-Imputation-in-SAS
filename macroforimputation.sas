%MACRO IMPV5(DSN=,VARS=,EXCLUDE=,PCTREM=1,MSTD=1000)/MINOPERATOR;
%PUT IMPUTE 5.0 IS NOW RUNNING;
/*
PCTREM = threshold for proportion of data missing/coded at which to drop the variable
MSTD = Maximum STDev
*/

*write nonessential log information to dummy file;
FILENAME LOG1 DUMMY;
PROC PRINTTO LOG=LOG1;
RUN;

/*file and data set references*/
%IF %INDEX(&DSN,.) %THEN %DO;
    %LET LIB=%UPCASE(%SCAN(&DSN,1,.));
    %LET DATA=%UPCASE(%SCAN(&DSN,2,.));
%END;
%ELSE %DO;
    %LET LIB=WORK;
    %LET DATA=%UPCASE(&DSN);
%END;

%LET DSID=%SYSFUNC(OPEN(&LIB..&DATA));
%LET NOBS=%SYSFUNC(ATTRN(&DSID,NOBS));
%LET CLOSE=%SYSFUNC(CLOSE(&DSID));

DATA TEMP;
    SET &LIB..&DATA;
RUN;

%IF %SYSEVALF(&PCTREM=1) %THEN %DO;
	/*store summary information for each variable*/
	PROC SQL;
		CREATE TABLE &LIB..&DATA.REC
		(VARNAME char(10),
		PROP_IMPUTE num,
		MIN num,
		MEDIAN num,
		MEAN num,
		MAX num,
		STD num,
		STD3 num,
		STD4 num,
		STD5 num,
		STD6 num,
		STD7 num,
		MAXSTD num);
	QUIT;
%END;

/*target dataset includes event variables that should be excluded from evaluation
if all variables are read without exclusion, this acts as a failsafe*/
%IF %UPCASE(&VARS)=_ALL_ AND &EXCLUDE= %THEN %DO;
	PROC PRINTTO;
	RUN;
	%PUT ============================================;
	%PUT XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX;
	%PUT ;
	%PUT XXX: EXCLUDE PARAMETER IS NULL;
	%PUT XXX: IMPUTE MACRO IS TERMINATING PREMATURELY;
	%PUT;
	%PUT XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX;
	%PUT ============================================;
	%RETURN;
%END;

%ELSE %DO;
	/*select variables to be imputed*/
	%IF %UPCASE(&VARS)=_ALL_ %THEN %DO;
		%LET NEXC=%SYSFUNC(COUNTW(&EXCLUDE,%STR( )));
		PROC SQL NOPRINT;
			SELECT NAME INTO: VARNAME SEPARATED BY ' '
			FROM DICTIONARY.COLUMNS
			WHERE UPCASE(LIBNAME)="&LIB" AND UPCASE(MEMNAME)="&DATA"
			AND UPCASE(NAME) NOT IN("%SCAN(%UPCASE(&EXCLUDE),1,%STR( ))" %DO A=2 %TO &NEXC;
			,"%SCAN(%UPCASE(&EXCLUDE),&A,%STR( ))"
			%END;);
		QUIT;
	%END;
	/*retain only relevant & excluded variables when operating on a subset*/
	%ELSE %DO;
		%LET VARNAME=&VARS;
		DATA TEMP;
			SET TEMP;
			KEEP &VARNAME &EXCLUDE;
		RUN;
	%END;
	/*iterate through selected variables for evaluation/imputation*/
	%DO B=1 %TO %SYSFUNC(COUNTW(&VARNAME,%STR( )));
		%LET CURR=%SCAN(&VARNAME,&B,%STR( ));
		/*check for missing observations. if all observations are missing, report and remove*/
		PROC SQL NOPRINT;
			SELECT NMISS(&CURR) INTO: MISS
				FROM TEMP;
		QUIT;
		%IF %SYSEVALF(&MISS=&NOBS) %THEN %DO;
			PROC PRINTTO;
			RUN;
			%PUT &CURR HAS NO OBSERVATIONS. &CURR HAS BEEN REMOVED;
			PROC PRINTTO LOG=LOG1;
			RUN;
			PROC SQL;
				ALTER TABLE TEMP
				DROP &CURR;
			QUIT;				
		%END;
		%ELSE %DO;
			/*evaluate variable for possible coded observations*/
			PROC MEANS DATA=TEMP(KEEP=&CURR) NOPRINT MAX;
				VAR &CURR;
				OUTPUT OUT=MAX MAX=MAX;
			RUN;		
			DATA _NULL_;
				SET MAX;
				CALL SYMPUTX('MAX',MAX);
			RUN;
			/*target dataset includes coded values for many variables, check for and evaluate accordingly*/
			%IF %EVAL(%SYSFUNC(INDEXW(%STR(9999999 9999 999 99 9.99 9.94 9.9999),&MAX))<1) %THEN %DO;
				%LET MAX=%SYSEVALF(&MAX+1);
				%LET LOW=&MAX;
			%END;
			%ELSE %DO;
				DATA _NULL_;
					IF &MAX=9.9999 THEN CALL SYMPUTX('LOW',9.9993);
					ELSE IF &MAX IN(9.99,9.94) THEN CALL SYMPUTX('LOW',9.93);
					ELSE CALL SYMPUTX('LOW',&MAX-6);
				RUN;
			%END;
			/*count missing and coded entries, then calculate proportion of observations counted vs total*/
			PROC SQL NOPRINT;
				SELECT COUNT(&CURR) INTO: CCODE
					FROM TEMP
					WHERE &CURR BETWEEN &LOW AND &MAX;
			QUIT;
			%LET PROP=%SYSEVALF((&CCODE+&MISS)/&NOBS);
			/*drop variables with too high proportion if not recording data*/
			%IF %SYSEVALF(&PROP>&PCTREM) AND %SYSEVALF(&PCTREM~=1) %THEN %DO;
				PROC SQL;
					ALTER TABLE TEMP
					DROP &CURR;
				QUIT;
				
				PROC PRINTTO;
				RUN;
				%PUT &CURR HAS BEEN REMOVED, TOO MUCH DATA IS CODED OR MISSING;
				PROC PRINTTO LOG=LOG1;
				RUN;
			%END;
			
			%ELSE %DO;
				/*summary statistics for recording and imputation*/
				PROC MEANS DATA=TEMP(KEEP=&CURR) NOPRINT MEDIAN STD MEAN MIN MAX;
					VAR &CURR;
					OUTPUT OUT=NUM MEDIAN=MEDIAN STD=STD MEAN=MEAN MIN=MIN MAX=MAX;
					WHERE &CURR<&LOW;
				RUN;
				/*save summary statistics for later use*/
				DATA _NULL_;
					SET NUM;
					CALL SYMPUTX('MEDIAN',MEDIAN);
					CALL SYMPUTX('STD',STD);
					CALL SYMPUTX('MEAN',MEAN);
					CALL SYMPUTX('MIN',MIN);
					CALL SYMPUTX('MAX',MAX);
				RUN;
				
				%IF %SYSEVALF(&PCTREM=1) %THEN %DO;	
					/*log summary data for each variable
					proportion of observations more than c standard deviations from mean*/
					%DO C=3 %TO 7;
						PROC SQL NOPRINT;
							SELECT COUNT(*) INTO: STD&C.
							FROM TEMP
							WHERE &CURR<&LOW AND &CURR NOT BETWEEN &MEAN-&STD*&C. AND &MEAN+&STD*&C.;
						QUIT;
						%LET STD&C.=%SYSEVALF(&&STD&C./&NOBS);
					%END;
					%LET MAXSTD=%SYSEVALF(%SYSFUNC(ABS(&MAX-&MEAN))/&STD);
					%LET MINSTD=%SYSEVALF(%SYSFUNC(ABS(&MIN-&MEAN))/&STD);
					/*set maxstd as std of value furthest from mean*/
					%IF %SYSEVALF(&MINSTD>&MAXSTD) %THEN %LET MAXSTD=&MINSTD;
					
					/*add entry to rec dataset for current variable*/
					PROC SQL NOPRINT;
						INSERT INTO &LIB..&DATA.REC
							VALUES("&CURR",&PROP,&MIN,&MEDIAN,&MEAN,&MAX,&STD,&STD3,&STD4,&STD5,&STD6,&STD7,&MAXSTD);
					QUIT;
				%END;
				/*if not recording and variable not previously dropped, impute missing/coded values*/
				%ELSE %DO;
					DATA TEMP;
						SET TEMP;
						IF &LOW<=&CURR | &CURR>&MEAN+&MSTD*&STD | &CURR<&MEAN-&MSTD*&STD | &CURR=. THEN &CURR=&MEDIAN;
					RUN;
				%END;			
			%END;
		%END;
	%END;
%END;

/*create new dataset from imputed dataset if not recording*/
%IF %SYSEVALF(&PCTREM~=1) %THEN %DO;
	DATA &LIB..&DATA.OUT;
		SET TEMP;
	RUN;
%END;
/*delete temporary working datasets*/
PROC DATASETS NOLIST;
	DELETE NUM TEMP MAX;
QUIT;

PROC PRINTTO;
RUN;
%PUT IMPV5 HAS FINISHED RUNNING HAVE A NICE DAY;

%MEND IMPV5;



