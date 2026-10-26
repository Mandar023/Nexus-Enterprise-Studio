USE [NTIS_4021]
GO
/****** Object:  StoredProcedure [Payment].[Prc_PropertyBalanceOffline]    Script Date: 8/19/2026 1:49:11 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--  [Payment].[Prc_PropertyBalanceOffline]   121982,'' ,GetPreviousReceipts,online
ALTER Procedure [Payment].[Prc_PropertyBalanceOffline] 
    @OwnerID INT = NULL,
	@PaymentType nvarchar(max) = NULL,
    @Flag nvarchar(max),
	@PageName nvarchar(max) = NULL,
	@StampMasterID INT = NULL,
	@UserID INT = NULL,
	@Date nvarchar(max) = NULL,
	@UniqID NVARCHAR(MAX)= null
AS
BEGIN
    -- Declare variables
    DECLARE @FinanceYear INT;
    DECLARE @PaidCurrentTax FLOAT = 0, @PaidPendingTax FLOAT = 0;


		Declare @PendingYearForParbhani nvarchar(20)
	declare @CouncilId int
	select top 1 @CouncilId=SrNo from CouncilMaster
	select @PendingYearForParbhani= OldWardNo from PropertyMast where OwnerID=@OwnerID

    -- Set the finance year
    SELECT @FinanceYear = ISNULL(MAX(FinanceYear), 0) FROM TransYearMast;

	Declare @PendingTotal money
	Declare @CurrentTotal money
	Declare @PendingMajorBuilding money
	Declare @CurrentMajorBuilding money
	Declare @PTotal money
	Declare @CTotal money

	IF @PaymentType = ''
	BEGIN
		SET @PaymentType = 'ALL'
	END

	IF @PaymentType = 'ALL'
	BEGIN
		set @PendingMajorBuilding=(select isnull(MajorBuilding,0) From dbo.ViewfunAMCGetPendingBalance WITH(NOLOCK) Where OwnerID=@OwnerID and pendingyear=@FinanceYear-1)
        set @CurrentMajorBuilding=(select isnull(MajorBuilding,0) From dbo.ViewfunAMCGetCurrentBalance WITH(NOLOCK) Where OwnerID=@OwnerID and FinanceYear=@FinanceYear)
		Set @PendingTotal= (Select ISNULL(PropertyTax,0)+ISNULL(EducationTax,0)+ISNULL(EmploymentTax,0)+ISNULL(TreeCess,0)+ISNULL(SpEducationTax,0)+ISNULL(Sanitation,0)+ISNULL(DrainCess,0)+ISNULL(SpWaterCess,0)+ISNULL(RoadCess,0)+ISNULL(FireCess,0)+ISNULL(LightCess,0)+ISNULL(WaterBenefit,0)+ISNULL(SewageDisposalCess,0)+ISNULL(WaterBill,0)+ISNULL(Tax1,0)+ISNULL(Tax2,0)+ISNULL(Tax3,0)  From dbo.ViewfunAMCGetPendingBalance WITH(NOLOCK) Where OwnerID=@OwnerID and pendingyear=@FinanceYear-1)
		Set @CurrentTotal= (Select ISNULL(PropertyTax,0)+ISNULL(EducationTax,0)+ISNULL(EmploymentTax,0)+ISNULL(TreeCess,0)+ISNULL(SpEducationTax,0)+ISNULL(Sanitation,0)+ISNULL(DrainCess,0)+ISNULL(SpWaterCess,0)+ISNULL(RoadCess,0)+ISNULL(FireCess,0)+ISNULL(LightCess,0)+ISNULL(WaterBenefit,0)+ISNULL(SewageDisposalCess,0)+ISNULL(WaterBill,0)+ISNULL(Tax1,0)+ISNULL(Tax2,0)+ISNULL(Tax3,0)  From dbo.ViewfunAMCGetCurrentBalance WITH(NOLOCK) Where OwnerID=@OwnerID and FinanceYear=@FinanceYear)
	END
	ELSE IF @PaymentType = 'Pending'
	BEGIN
		Set @PendingTotal= (Select ISNULL(PropertyTax,0)+ISNULL(EducationTax,0)+ISNULL(EmploymentTax,0)+ISNULL(TreeCess,0)+ISNULL(SpEducationTax,0)+ISNULL(Sanitation,0)+ISNULL(DrainCess,0)+ISNULL(SpWaterCess,0)+ISNULL(RoadCess,0)+ISNULL(FireCess,0)+ISNULL(LightCess,0)+ISNULL(WaterBenefit,0)+ISNULL(SewageDisposalCess,0)+ISNULL(WaterBill,0)+ISNULL(Tax1,0)+ISNULL(Tax2,0)+ISNULL(Tax3,0) From dbo.ViewfunAMCGetPendingBalance WITH(NOLOCK) Where OwnerID=@OwnerID and pendingyear=@FinanceYear-1)
		set @PendingMajorBuilding=(select isnull(MajorBuilding,0) From dbo.ViewfunAMCGetPendingBalance WITH(NOLOCK) Where OwnerID=@OwnerID and pendingyear=@FinanceYear-1)
		Set @CurrentTotal= 0
		   set @CurrentMajorBuilding=0
	END
	

    -- Temporary table for penalties
    Create Table #Temp_Interest(OwnerID int,PayableCurrentPenalty float,PayablePendingPenalty float,
		PayablePropertyTaxCurrentPenalty float,PayablePropertyTaxPendingPenalty float,
		PayableTax1CurrentPenalty float,PayableTax1PendingPenalty float,
		PayableEducationTaxCurrentPenalty float,PayableEducationTaxPendingPenalty float,
		PayableEmploymentTaxCurrentPenalty float,PayableEmploymentTaxPendingPenalty float)

IF @OwnerID IS NOT NULL
BEGIN
	Insert into #Temp_Interest
	Exec [Online].[Prc_GetPenalty_Interest]@OwnerID,@FinanceYear
END

    -- Temporary tables for transaction and tax pending details
    SELECT * INTO #Temp_TransMast 
    FROM Tab.View_GetCurrentBalance 
    WHERE OwnerID = @OwnerID AND FinanceYear = @FinanceYear;

	update #Temp_TransMast set TaxTotal=ISNULL(PropertyTax,0)+ISNULL(EducationTax,0)+ISNULL(EmploymentTax,0)+ISNULL(TreeCess,0)+ISNULL(SpEducationTax,0)+ISNULL(Sanitation,0)+ISNULL(DrainCess,0)+ISNULL(SpWaterCess,0)+ISNULL(RoadCess,0)+ISNULL(FireCess,0)+ISNULL(LightCess,0)+ISNULL(WaterBenefit,0)+ISNULL(SewageDisposalCess,0)+ISNULL(WaterBill,0)+ISNULL(Tax1,0)+ISNULL(Tax3,0)+ISNULL(MajorBuilding,0)

    SELECT * INTO #Temp_TaxPendingDetails 
    FROM Tab.View_GetPendingBalance 
    WHERE OwnerID = @OwnerID AND PendingYear = (@FinanceYear - 1);

	update #Temp_TaxPendingDetails set TaxTotal=ISNULL(PropertyTax,0)+ISNULL(EducationTax,0)+ISNULL(EmploymentTax,0)+ISNULL(TreeCess,0)+ISNULL(SpEducationTax,0)+ISNULL(Sanitation,0)+ISNULL(DrainCess,0)+ISNULL(SpWaterCess,0)+ISNULL(RoadCess,0)+ISNULL(FireCess,0)+ISNULL(LightCess,0)+ISNULL(WaterBenefit,0)+ISNULL(SewageDisposalCess,0)+ISNULL(WaterBill,0)+ISNULL(Tax1,0)+ISNULL(Tax3,0)+ISNULL(MajorBuilding,0)

    -- CTE for current taxes
    ;WITH CurrentTaxesCTE AS (
        SELECT 'PropertyTax' AS TaxName, ISNULL(PropertyTax, 0) AS CurrentTaxes FROM #Temp_TransMast UNION ALL 
        SELECT 'EducationTax', ISNULL(EducationTax, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'EmploymentTax', ISNULL(EmploymentTax, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'SpEducationTax', ISNULL(SpEducationTax, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'DrainCess', ISNULL(DrainCess, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'RoadCess', ISNULL(RoadCess, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'TreeCess', ISNULL(TreeCess, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'SewageDisposalCess', ISNULL(SewageDisposalCess, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'Sanitation', ISNULL(Sanitation, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'WaterBenefit', ISNULL(WaterBenefit, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'SpWaterCess', ISNULL(SpWaterCess, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'WaterBill', ISNULL(WaterBill, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'FireCess', ISNULL(FireCess, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'MajorBuilding', ISNULL(MajorBuilding, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'LightCess', ISNULL(LightCess, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'Tax1', ISNULL(Tax1, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'Tax2', ISNULL(Tax2, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'Tax3', ISNULL(Tax3, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'Tax4', ISNULL(Tax4, 0) FROM #Temp_TransMast UNION ALL
        SELECT 'Tax5', ISNULL(Tax5, 0) FROM #Temp_TransMast UNION ALL
		SELECT 'Interest', ISNULL(PayableCurrentPenalty, 0) FROM #Temp_Interest UNION ALL
		SELECT 'PropertyTaxInterest', ISNULL(PayablePropertyTaxCurrentPenalty, 0) FROM #Temp_Interest UNION ALL
		SELECT 'Tax1Interest', ISNULL(PayableTax1CurrentPenalty, 0) FROM #Temp_Interest UNION ALL
		SELECT 'EducationTaxInterest', ISNULL(PayableEducationTaxCurrentPenalty, 0) FROM #Temp_Interest UNION ALL
		SELECT 'EmploymentTaxInterest', ISNULL(PayableEmploymentTaxCurrentPenalty, 0) FROM #Temp_Interest UNION ALL
        SELECT 'TaxTotal', ISNULL(TaxTotal, 0) FROM #Temp_TransMast
    )
    SELECT * INTO #Temp_CurrentTax FROM CurrentTaxesCTE;
	print '1111111'
    -- CTE for pending taxes
    ;WITH PendingTaxesCTE AS (
        SELECT 'PropertyTax' AS TaxName, ISNULL(PropertyTax, 0) AS PendingTaxes FROM #Temp_TaxPendingDetails UNION ALL 
        SELECT 'EducationTax', ISNULL(EducationTax, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'EmploymentTax', ISNULL(EmploymentTax, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'SpEducationTax', ISNULL(SpEducationTax, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'DrainCess', ISNULL(DrainCess, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'RoadCess', ISNULL(RoadCess, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'TreeCess', ISNULL(TreeCess, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'SewageDisposalCess', ISNULL(SewageDisposalCess, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'Sanitation', ISNULL(Sanitation, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'WaterBenefit', ISNULL(WaterBenefit, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'SpWaterCess', ISNULL(SpWaterCess, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'WaterBill', ISNULL(WaterBill, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'FireCess', ISNULL(FireCess, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'MajorBuilding', ISNULL(MajorBuilding, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'LightCess', ISNULL(LightCess, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'Tax1', ISNULL(Tax1, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'Tax2', ISNULL(Tax2, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'Tax3', ISNULL(Tax3, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'Tax4', ISNULL(Tax4, 0) FROM #Temp_TaxPendingDetails UNION ALL
        SELECT 'Tax5', ISNULL(Tax5, 0) FROM #Temp_TaxPendingDetails UNION ALL
		SELECT 'Interest', ISNULL(PayablePendingPenalty, 0) FROM #Temp_Interest UNION ALL
        SELECT 'PropertyTaxInterest', ISNULL(PayablePropertyTaxPendingPenalty, 0) FROM #Temp_Interest UNION ALL
		SELECT 'Tax1Interest', ISNULL(PayableTax1PendingPenalty, 0) FROM #Temp_Interest UNION ALL
		SELECT 'EducationTaxInterest', ISNULL(PayableEducationTaxPendingPenalty, 0) FROM #Temp_Interest UNION ALL
		SELECT 'EmploymentTaxInterest', ISNULL(PayableEmploymentTaxPendingPenalty, 0) FROM #Temp_Interest UNION ALL
        SELECT 'TaxTotal', ISNULL(TaxTotal, 0)  FROM #Temp_TaxPendingDetails
    )
    SELECT * INTO #Temp_PendingTax FROM PendingTaxesCTE;

    -- Prepare result table with tax names and display order
    SELECT TaxNameAlias AS TaxNameMarathi, TaxnName AS TaxName, 0 AS CurrentTaxes, 0 AS PendingTaxes, DisplayOrder
    INTO #Temp_Result
    FROM Online.ApplyTaxesMaster
    WHERE Status = 1 AND TaxnName NOT IN ('NetTotal','Discount','TotalTax') order by DisplayOrder ;


	-- select * from #Temp_Result order by DisplayOrder asc

	--Create Table #Temp_Discount1(
	--	SrNo Int,DiscountName nvarchar(max),
	--	DiscountAliasName nvarchar(max),
	--	DiscountDiscription nvarchar(max),
	--	CurrentDiscountTaxTotal float,
	--	PendingDiscountTaxTotal float,
	--	DiscountPercentage float,
	--	CurrentDiscountApplied float,
	--	PendingDiscountApplied float,
	--	TotalDiscountApplied float,
	--	TotalCurrentDiscount float,
	--	TotalPendingDiscount float,
	--	TotalDiscount float,
	--	BTDiscountColumn nvarchar(max),
	--	BTDiscountPercentageColumn nvarchar(max)

	--)
	--Insert into #Temp_Discount1
	--EXEC [propertytax].[Prc_GetDiscount] @OwnerID, @CurrentTotal, @PendingTotal, @PageName;



	UPDATE A 
    SET A.CurrentTaxes = A.CurrentTaxes + (Select SUM(ISNULL(PayableCurrentPenalty,0)) from #Temp_Interest)
    FROM #Temp_CurrentTax AS A
	Where A.TaxName='Taxtotal';
	
    UPDATE A 
    SET A.PendingTaxes = A.PendingTaxes + (Select SUM(ISNULL(PayableCurrentPenalty,0)) from #Temp_Interest)
    FROM #Temp_PendingTax AS A
	Where A.TaxName='Taxtotal';


    -- Update result table with actual tax data (current and pending)
    UPDATE A 
    SET A.CurrentTaxes = B.CurrentTaxes
    FROM #Temp_Result AS A
    INNER JOIN #Temp_CurrentTax AS B ON A.TaxName = B.TaxName;

    UPDATE A 
    SET A.PendingTaxes = B.PendingTaxes
    FROM #Temp_Result AS A
    INNER JOIN #Temp_PendingTax AS B ON A.TaxName = B.TaxName;

	--Declare @Discount float= (Select SUM(TotalDiscountApplied) from #Temp_Discount1);
	--Update #Temp_Result Set CurrentTaxes= (Select CurrentTaxes from #Temp_Result where TaxName = 'TaxTotal') - (Select SUM(TotalDiscountApplied) from #Temp_Discount1) where TaxName = 'TaxTotal'
	--print @Discount
    -- Return data based on ResultSetType
	IF @Flag = 'ChkNotavari'
    BEGIN
        -- Execute stored procedure for discounts
        Select * from Online.NotvariCollectionDetails where CONVERT(NVARCHAR(MAX),CreatedDate,23)=@Date and CashierID=@UserID
    END
    IF @Flag = 'GetDiscount'
    BEGIN
        -- Execute stored procedure for discounts
        EXEC [propertytax].[Prc_GetDiscount] @OwnerID,  @PendingTotal,@CurrentTotal, @PageName; 
    END
    ELSE IF @Flag = 'GetInterest'
    BEGIN
		--if @PendingTotal>0 or @CurrentTotal>0
		--Begin
  --      Select Convert(int,@PendingTotal) AS PendingTotal, Convert(int,@CurrentTotal) AS CurrentTotal,PayableCurrentPenalty AS TotalCurrentInterest,  PayablePendingPenalty AS TotalPendingInterest From #Temp_Interest WITH(NOLOCK)
		--End
		--else
		--Begin
		--	Select 0 AS PendingTotal, 0 AS CurrentTotal,PayableCurrentPenalty AS TotalCurrentInterest,  PayablePendingPenalty AS TotalPendingInterest From #Temp_Interest WITH(NOLOCK)
		--End

		if @PendingTotal>0 or @CurrentTotal>0
		Begin
		print @PendingMajorBuilding
			Select Convert(int,@PendingTotal) AS PendingTotal, Convert(int,@CurrentTotal) AS CurrentTotal,
			PayableCurrentPenalty+@CurrentMajorBuilding AS TotalCurrentInterest,PayablePendingPenalty+@PendingMajorBuilding AS TotalPendingInterest  From #Temp_Interest WITH(NOLOCK)
		End

		else
		Begin
		       if @PendingTotal>0 and @CurrentTotal>0
		begin
		
			Select 0 AS PendingTotal, 0 AS CurrentTotal,PayableCurrentPenalty AS TotalCurrentInterest,  PayablePendingPenalty AS TotalPendingInterest From #Temp_Interest WITH(NOLOCK)
			end
			else 
			begin
			Select 0 AS PendingTotal, 0 AS CurrentTotal,0 AS TotalCurrentInterest,  0 AS TotalPendingInterest From #Temp_Interest WITH(NOLOCK)
		End
		end
    END
    ELSE IF @Flag = 'GetChequeBounceFee'
    BEGIN
        exec Online.PrcGetChequeBounceFeeChecking @OwnerID
    END
    ELSE IF @Flag = 'GetTaxesHeadwise'
    BEGIN
		--Select TaxNameMarathi,TaxName,PendingTaxes,CurrentTaxes,DisplayOrder from #Temp_Result
        --IF(Select  DefaultValue_Bit AS IsDistributedInterest From Collective.ApplicationSetting Where FlagName='IsDistributedInterest'and ModuleID in (Select ModuleID From UserModule.ModuleMaster Where ModuleName = 'PropertyTax'))=1
			BEGIN

				;with CTE as (
				
				Select TaxNameMarathi,TaxName,PendingTaxes,CurrentTaxes,DisplayOrder,@FinanceYear as FinanceYear,case when isnull(@CouncilId,0)=5024 and isnull(@PendingYearForParbhani,0)!=0  then @PendingYearForParbhani else (@FinanceYear-1) end as PendingYear from #Temp_Result 
				--Union all
				--select N'मनपा कर विलंब दंड'AS TaxNameMarathi,'PropertyTaxInterest'AS TaxName ,
				--isnull(cast((Select isnull(PayablePropertyTaxPendingPenalty,0) from #Temp_Interest with(nolock)  )as int),0) AS PendingTaxes,
				--isnull(cast((Select isnull(PayablePropertyTaxCurrentPenalty,0) from #Temp_Interest with(nolock)  )as int),0) AS CurrentTaxes,
				--13 AS DisplayOrder 
				--union all
				--select N'शिक्षण कर विलंब दंड'AS TaxNameMarathi,'EducationTaxInterest'AS TaxName ,
				--isnull(cast((Select isnull(PayableEducationTaxPendingPenalty,0) from #Temp_Interest with(nolock)  )as int),0) AS PendingTaxes,
				--isnull(cast((Select isnull(PayableEducationTaxCurrentPenalty,0) from #Temp_Interest with(nolock)  )as int),0) AS CurrentTaxes,
				--16 AS DisplayOrder  
				--union all
				--select N'रोजगार हमी कर विलंब दंड'AS TaxNameMarathi,'EmploymentTaxInterest'AS TaxName,
				--isnull(cast((Select isnull(PayableEmploymentTaxPendingPenalty,0) from #Temp_Interest with(nolock)  )as int),0) AS PendingTaxes,
				--isnull(cast((Select isnull(PayableEmploymentTaxCurrentPenalty,0) from #Temp_Interest with(nolock)  )as int),0) AS CurrentTaxes,
				--15 AS DisplayOrder 
				--union all
				--select N'फ्लोअरेज कर विलंब दंड'AS TaxNameMarathi,'Tax1Interest'AS TaxName ,
				--isnull(cast((Select isnull(PayableTax1PendingPenalty,0) from #Temp_Interest with(nolock)  )as int),0) AS PendingTaxes,
				--isnull(cast((Select isnull(PayableTax1CurrentPenalty,0) from #Temp_Interest with(nolock)  )as int),0) AS CurrentTaxes,
				--14 AS DisplayOrder 
				)


				
				Select * from CTE AS A 
				--where (PendingTaxes >0 or CurrentTaxes>0) 
				/*union all
				select N'पाणीपट्टी कर रु.'AS TaxNameMarathi,'WaterBenefit'AS TaxName ,
				isnull(cast((Select isnull(WaterBenefit,0) from #Temp_TaxPendingDetails with(nolock)  )as int),0) AS PendingTaxes,
				isnull(cast((Select isnull(WaterBenefit,0) from #Temp_TransMast with(nolock)  )as int),0) AS CurrentTaxes,
				5 AS DisplayOrder
				union all
				select N'स्वच्छता कर रु.'AS TaxNameMarathi,'SewageDisposalCess'AS TaxName ,
				isnull(cast((Select isnull(SewageDisposalCess,0) from #Temp_TaxPendingDetails with(nolock)  )as int),0) AS PendingTaxes,
				isnull(cast((Select isnull(SewageDisposalCess,0) from #Temp_TransMast with(nolock)  )as int),0) AS CurrentTaxes,
				8 AS DisplayOrder */ --double added
				--union all
				--select N'रोजगार हमी कर रु.'AS TaxNameMarathi,'EmploymentTax'AS TaxName ,
				--isnull(cast((Select isnull(EmploymentTax,0) from #Temp_TaxPendingDetails with(nolock)  )as int),0) AS PendingTaxes,
				--isnull(cast((Select isnull(EmploymentTax,0) from #Temp_TransMast with(nolock)  )as int),0) AS CurrentTaxes,
				--10 AS DisplayOrder 
				/*Union all
				select N'मोठी इमारत कर रु.'AS TaxNameMarathi,'Tax1'AS TaxName ,
				isnull(cast((Select isnull(Tax1,0) from #Temp_TaxPendingDetails with(nolock)  )as int),0) AS PendingTaxes,
				isnull(cast((Select isnull(Tax1,0) from #Temp_TransMast with(nolock)  )as int),0) AS CurrentTaxes,
				11 AS DisplayOrder */--double added
				/*Union all
				select N'थकीत शास्ती रु.'AS TaxNameMarathi,'MajorBuilding'AS TaxName ,
				isnull(cast((Select isnull(MajorBuilding,0) from #Temp_TaxPendingDetails with(nolock)  )as int),0) AS PendingTaxes,
				isnull(cast((Select isnull(MajorBuilding,0) from #Temp_TransMast with(nolock)  )as int),0) AS CurrentTaxes,
				14 AS DisplayOrder */ --double added
				Union all
				select N' एकूण कर रु.'AS TaxNameMarathi,'TaxTotal'AS TaxName ,
				(Select SUM(PendingTaxes)  from #Temp_Result) AS PendingTaxes,
				(Select SUM(CurrentTaxes)  from #Temp_Result) AS CurrentTaxes,
				100 AS DisplayOrder,@FinanceYear as FinanceYear,case when isnull(@CouncilId,0)=5024 and isnull(@PendingYearForParbhani,0)!=0  then @PendingYearForParbhani else (@FinanceYear-1) end as PendingYear
				Union all
				select N'विशेष सूट'AS TaxNameMarathi,'Discount'AS TaxName ,
				0 AS PendingTaxes,
				0 AS CurrentTaxes,
				101 AS DisplayOrder,@FinanceYear as FinanceYear,case when isnull(@CouncilId,0)=5024 and isnull(@PendingYearForParbhani,0)!=0  then @PendingYearForParbhani else (@FinanceYear-1) end as PendingYear

				UNION ALL
				select N'निव्वळ एकूण कर रु.'AS TaxNameMarathi,'NetTotal'AS TaxName ,
				0,0,
				--(Select SUM(PendingTaxes)  from #Temp_Result) AS PendingTaxes,
				--(Select SUM(CurrentTaxes)  from #Temp_Result) AS CurrentTaxes,
				102 AS DisplayOrder,@FinanceYear as FinanceYear,case when isnull(@CouncilId,0)=5024 and isnull(@PendingYearForParbhani,0)!=0  then @PendingYearForParbhani else (@FinanceYear-1) end as PendingYear
				order by A.DisplayOrder
			END
			--ELSE
			--BEGIN
			--	select  TaxNameMarathi,TaxName,PreviousTaxes,CurrentTaxes from (Select TaxNameMarathi,TaxName,PendingTaxes,CurrentTaxes,DisplayOrder from #Temp_Result
			--	Union all
			--	Select N'शास्ती' AS TaxNameMarathi,'Interest' AS TaxName,
			--	isnull(cast((Select isnull(Interest,0) from #Temp_D_TaxesMast with(nolock)  where  FinanceYear=@FinanceYear and PendingYear=@FinanceYear - 1 and  RecordType=1)as int),0) AS PreviousTaxes,
			--	isnull(cast((Select isnull(Interest,0) from #Temp_D_TaxesMast with(nolock)  where  FinanceYear=@FinanceYear and PendingYear=@FinanceYear - 1 and  RecordType=1)as int),0) AS CurrentTaxes, 
			--	order by A.DisplayOrder
			--END
		
    END
	--IF @Flag = 'GetPreviousReceipts'
 --   BEGIN
	--	select MAX(bm.OwnerID) OwnerID,GlobalReceiptNo,InvoiceNo,BillBookNo, convert(varchar, bm.FinanceYear)+'-'+isnull(BillBookNo,'NA')+'-'+convert(varchar, bm.InvoiceNo) as ReceiptID, 
	--	max(bm.Amount) as Amount,
	--	 (select DefaultValue_Bit from Collective.ApplicationSetting where FlagName='ShowEditDate') as IsShowEditDate,
 --		--convert(varchar, MAX(bm.TransactionDate), 103)+' '+convert(varchar, MAX(bm.TransactionDate), 108) as TransactionDate ,
	--	 FORMAT(Max(TransactionDate), 'dd-MM-yyyy hh:mm tt') as TransactionDate,
	--	max(isnull(bm.MerchantTxnRefNumber,0)) as MerchantTxnRefNumber, 
	--	max((case when isnull(bm.PaymentResource,'')='offline' then 'Counter Payment' WHEN ISNULL(bm.PaymentResource, '') = 'NTIS' THEN 'Offline Posting' else isnull(bm.PaymentResource,'Offline Posting') end)) as PaymentResource, 
	--	max(isnull(PaymentMode,'')) as PaymentMode, max(case when isnull(ChequeStatus,'')='' then '-' else ChequeStatus end ) as ChequeStatus,FinanceYear,
	--	ISNULL(OtherFeeHeadName,'') as OtherFeeHeadName,
	--	 (select DefaultValue_Bit from collective.ApplicationSetting where FlagName ='IsDownloadCounterTabReceipt') as IsDownloadCounterTabReceipt
	--	from BillTransactionDetails bm with(nolock) right join PropertyMast pm with(nolock) on bm.OwnerID=pm.OwnerID where bm.OwnerID=@OwnerID  --and isnull(bm.Remark,'')!='Advance' 
	--	and isnull(InvoiceNo,'')<>'' and isnull(OtherFeeHeadName,'')=''
	--	group by InvoiceNo,bm.OwnerID,bm.FinanceYear,BillBookNo,GlobalReceiptNo ,OtherFeeHeadName
	--	--order by TransactionDate desc  
	--	ORDER BY MAX(bm.TransactionDate)
	--	--FinanceYear
	--	DESC
	--END
	IF @Flag = 'GetPreviousReceipts'
BEGIN
    SELECT 
        MAX(bm.OwnerID) AS OwnerID,
        (CASE 
				WHEN Isnull(CounterReceiptNo,'') ='' THEN CONCAT(Isnull(BillBookNo,''), '-', Isnull(InvoiceNo,0))
				ELSE CounterReceiptNo 
				END) AS GlobalReceiptNo,
        bm.InvoiceNo,
        bm.BillBookNo,
        CONVERT(VARCHAR, bm.FinanceYear) 
        + '-' + ISNULL(bm.BillBookNo, 'NA') 
        + '-' + CONVERT(VARCHAR, bm.InvoiceNo) AS ReceiptID,
        MAX(bm.Amount) AS Amount,
        (SELECT DefaultValue_Bit
         FROM Collective.ApplicationSetting
         WHERE FlagName = 'ShowEditDate') AS IsShowEditDate,
        FORMAT(MAX(bm.TransactionDate), 'dd-MM-yyyy hh:mm tt') AS TransactionDate,
        MAX(ISNULL(bm.MerchantTxnRefNumber, 0)) AS MerchantTxnRefNumber,
        MAX(
            CASE
                WHEN ISNULL(bm.PaymentResource, '') = 'offline' THEN 'Counter Payment'
                WHEN ISNULL(bm.PaymentResource, '') = 'NTIS' THEN 'Offline Posting'
                ELSE ISNULL(bm.PaymentResource, 'Offline Posting')
            END
        ) AS PaymentResource,
        MAX(ISNULL(bm.PaymentMode, '')) AS PaymentMode,
        MAX(
            CASE
                WHEN ISNULL(bm.ChequeStatus, '') = '' THEN '-'
                ELSE bm.ChequeStatus
            END
        ) AS ChequeStatus,
        bm.FinanceYear,
        ISNULL(bm.OtherFeeHeadName, '') AS OtherFeeHeadName,
        (SELECT DefaultValue_Bit
         FROM Collective.ApplicationSetting
         WHERE FlagName = 'IsDownloadCounterTabReceipt') AS IsDownloadCounterTabReceipt,
        MAX(
            CASE
                WHEN ISNULL(bm.Remark, '') IN ('Advance', 'AdvancePayment') 
                     AND bm.FinanceYear < @FinanceYear THEN 10
                ELSE 0
            END
        ) AS manageid,
        MAX(
            CASE
                WHEN ISNULL(bm.Remark, '') IN ('Advance', 'AdvancePayment')
                     AND bm.FinanceYear < @FinanceYear
                    THEN 'Due To Advance Payment, Receipt Download Is Not Allowed'
                ELSE ''
            END
        ) AS message
    FROM BillTransactionDetails bm WITH (NOLOCK)
    RIGHT JOIN PropertyMast pm WITH (NOLOCK)
        ON bm.OwnerID = pm.OwnerID
    WHERE bm.OwnerID = @OwnerID
      AND bm.InvoiceNo IS NOT NULL
      --AND ISNULL(bm.OtherFeeHeadName, '') = ''
    GROUP BY
        bm.InvoiceNo,
        bm.OwnerID,
        bm.FinanceYear,
        bm.BillBookNo,
        bm.GlobalReceiptNo,
		CounterReceiptNo,
        bm.OtherFeeHeadName
    ORDER BY MAX(bm.TransactionDate) DESC
END
	IF @Flag = 'GetOtherPreviousReceipts'
    BEGIN
		select MAX(bm.OwnerID) OwnerID,GlobalReceiptNo,InvoiceNo,BillBookNo, convert(varchar, bm.FinanceYear)+'-'+isnull(BillBookNo,'NA')+'-'+convert(varchar, bm.InvoiceNo) as ReceiptID, 
		max(bm.Amount) as Amount,
		--convert(varchar, MAX(bm.TransactionDate), 103)+' '+convert(varchar, MAX(bm.TransactionDate), 108) as TransactionDate ,
		 Max(TransactionDate) as TransactionDate,
		max(isnull(bm.MerchantTxnRefNumber,0)) as MerchantTxnRefNumber, 
		max((case when isnull(bm.PaymentResource,'')='offline' then 'Counter Payment' else isnull(bm.PaymentResource,'NTIS') end)) as PaymentResource, 
		max(isnull(PaymentMode,'')) as PaymentMode, max(case when isnull(ChequeStatus,'(')='' then '-' else ChequeStatus end ) as ChequeStatus,FinanceYear,ISNULL(OtherFeeHeadName,'Other Payment') as OtherFeeHeadName 
		from BillTransactionDetails bm with(nolock) right join PropertyMast pm with(nolock) on bm.OwnerID=pm.OwnerID where bm.OwnerID=@OwnerID  and isnull(bm.Remark,'')!='Advance' and isnull(InvoiceNo,'')<>'' AND ISNULL(OtherFeeHeadName,'') != ''
		group by InvoiceNo,bm.OwnerID,bm.FinanceYear,BillBookNo,GlobalReceiptNo ,OtherFeeHeadName
		order by TransactionDate desc
	END

	--SELECT TOP 10 * FROM BillTransactionDetails ORDER BY TRANSACTIONDATE DESC
	--select convert(varchar, MAX(bm.TransactionDate), 103),convert(varchar, MAX(bm.TransactionDate), 108) transactionDate, bm.TransactionDate from BillTransactionDetails bm  group by TransactionDate

    -- Cleanup temp tables
    DROP TABLE #Temp_Interest;
    DROP TABLE #Temp_TransMast;
    DROP TABLE #Temp_TaxPendingDetails;
    DROP TABLE #Temp_CurrentTax;
    DROP TABLE #Temp_PendingTax;
    DROP TABLE #Temp_Result;
	--DROP TABLE #Temp_Discount1;

END;
