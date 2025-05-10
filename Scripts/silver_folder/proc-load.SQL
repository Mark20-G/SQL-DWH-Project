/*
========================================================
stored procedure- load silver layer
========================================================
script purpose: loading data into the 'silver' schema from 'bronze' layer tables, after data cleansing and transformations,
========================================================
*/
create or alter procedure silver.load_silver as
begin
	declare @start_time datetime, @end_time datetime, @batch_start_time datetime, @batch_end_time datetime;
 begin try
	print '====================================================================';
	print 'loading silver layer';
	print '====================================================================';

	print '--------------------------------------------------------------------';
	print 'loading crm tables';
	print '--------------------------------------------------------------------';
	set @batch_start_time=GETDATE();
	set @start_time=GETDATE();
	print '>>truncating table cust_info';
	truncate table silver.crm_cust_info;
	print '>>inserting data into table cust_info';
	insert into silver.crm_cust_info(
	cst_id,
	cst_key,
	cst_firstname,
	cst_lastname,
	cst_marital_status,
	cst_gndr,
	cst_create_date)

	select
	cst_id,
	trim(cst_key) as cst_key, --remove unwanted spaces
	trim(cst_firstname)as cst_firstname, --remove unwanted spaces
	trim(cst_lastname) as cst_lastname, --remove unwanted spaces
	case 
	when upper(trim(cst_marital_status)) like 'M' then 'Married'
	when upper(trim(cst_marital_status)) like 'S' then 'Single'
	else 'N/A'
	end as cst_marital_status , --normalize marital status values and set default value
	case
	when upper(trim(cst_gndr)) like 'M' then 'Male'
	when upper(trim(cst_gndr)) like 'F'  then 'Female'
	else 'N/A'
	end as cst_gndr , --normalize gender values and set default value
	cst_create_date
	from(
	select
	*,
	row_number() over (partition by cst_id order by cst_create_date desc) as ranking
	from bronze.crm_cust_info ) as ranked_by_crt_date
	where ranking=1 and cst_id is not null --remove duplicates
	set @end_time=GETDATE();
	print 'loading duration: '+ cast(datediff(second,@start_time,@end_time) as nvarchar)+' seconds'
	print' -------------------------------------------------------------------------------'

	set @start_time=GETDATE();
	print '>>truncating table prd_info';
	truncate table silver.crm_prd_info;
	print '>>inserting data into table prd_info';
	insert into silver.crm_prd_info(
	prd_id,
	cat_id,
	prd_key,
	prd_nm,
	prd_cost,
	prs_line,
	prd_start_dt,
	prd_end_dt)

	select
	prd_id,
	replace(substring(trim(prd_key),1,5),'-','_') as cat_id, --create a unique column for the category id part in prd_key, and switching '-' into '_' so it fits to the same naming convention as in the erp product table
	substring(trim(prd_key),7,LEN(prd_key)) as prd_key, --create a unique column for the product key after taking away the category part from prd_key
	trim(prd_nm) as prd_nm, -- remove unwanted spaces
	case
	when prd_cost is not null then prd_cost
	else 0
	end as prd_cost, --create default value and remove nulls from cost column
	case 
	when upper(trim(prs_line))='M' then 'Mountain'
	when upper(trim(prs_line))='R' then 'Road'
	when upper(trim(prs_line))='T' then 'Touring'
	when upper(trim(prs_line))='S' then 'Sport'
	else 'N/A'
	end as prs_line, --normalize line values and set default value
	cast(prd_start_dt as date) as prd_start_dt, -- transform into date type
	cast(DATEADD(DAY, -1,lead(prd_start_dt) over (partition by prd_key order by prd_start_dt)) as date) as prd_end_dt --fix end date so it would be logically correct
	from bronze.crm_prd_info
	set @end_time=GETDATE();
	print 'loading duration: '+ cast(datediff(second,@start_time,@end_time) as nvarchar)+' seconds'
	print' -------------------------------------------------------------------------------'

	set @start_time=GETDATE();
	print '>>truncating table sales_details';
	truncate table silver.crm_sales_details;
	print '>>inserting data into table sales_details';
	insert into silver.crm_sales_details(
	sls_ord_num,
	sls_prd_key,
	sls_cust_id,
	sls_order_dt,
	sls_ship_dt,
	sls_due_dt,
	sls_sales,
	sls_quantity,
	sls_price )

	select 
	sls_ord_num,
	sls_prd_key,
	sls_cust_id,
	case 
	when len(sls_order_dt)!=8 or sls_order_dt=0 then null 
	else cast(cast(sls_order_dt as varchar) as date)
	end as sls_order_dt, --Convert into valid date and remove unreasonable numbers
	case 
	when len(sls_ship_dt)!=8 or sls_ship_dt=0 then null 
	else cast(cast(sls_ship_dt as varchar) as date)
	end as sls_ship_dt, --Convert into valid date and remove unreasonable numbers
	case
	when len(sls_due_dt)!=8 or sls_due_dt=0 then null 
	else cast(cast(sls_due_dt as varchar) as date)
	end as sls_due_dt, --Convert into valid date and remove unreasonable numbers
	case
	when sls_sales<=0 or sls_sales is null or sls_sales!=ABS(sls_price)*sls_quantity 
	then ABS(sls_price)*sls_quantity 
	else sls_sales
	end as sls_sales, --fix to a logically correct number
	sls_quantity,
	case 
	when sls_price is null or sls_price<=0
	then sls_sales/ nullif( sls_quantity,0)
	else sls_price
	end as sls_price --fix to a logically correct number
	from bronze.crm_sales_details
	set @end_time=GETDATE();
	print 'loading duration: '+ cast(datediff(second,@start_time,@end_time) as nvarchar)+' seconds'
	print' -------------------------------------------------------------------------------'

	print '--------------------------------------------------------------------';
	print 'loading erp tables';
	print '--------------------------------------------------------------------';

	set @start_time=GETDATE();
	print '>>truncating table cust_az12';
	truncate table silver.erp_cust_az12;
	print '>>inserting data into table cust_ez12';
	insert into silver.erp_cust_az12(
	cid,
	bdate,
	gen)

	select 
	case
	when cid like 'NAS%' then SUBSTRING(cid,4,len(trim(cid)))
	else cid
	end as cid,--remove unknown string to match the same naming convention as in the crm table
	case when bdate>GETDATE() or year(bdate)<1925 then null
	else bdate
	end as bdate, --remove impossible dates
	case 
	when upper(Trim(gen)) in ('F','Female') then 'Female'
	when upper(Trim(gen)) in ('M','Male') then 'Male'
	else 'N/A'
	end as gen --normalize gender values and set a default value
	from bronze.erp_cust_az12
	set @end_time=GETDATE();
	print 'loading duration: '+ cast(datediff(second,@start_time,@end_time) as nvarchar)+' seconds'
	print' -------------------------------------------------------------------------------'

	set @start_time=GETDATE();
	print '>>truncating table loc_a101';
	truncate table silver.erp_loc_a101;
	print '>>inserting data into table loc_a101';
	insert into silver.erp_loc_a101(
	cid,
	cntry)

	select 
	replace(cid,'-','') as cid, --remove char so the string would fit to the naming convention
	case 
	when lower(trim(cntry)) in ('us','usa') then 'United States'
	when lower(trim(cntry))='de' then 'Germany'
	when trim(cntry)='' or cntry is null then 'N/A'
	else trim(cntry)
	end as cntry --Normalize country values and set default value
	from bronze.erp_loc_a101
		set @end_time=GETDATE();
	print 'loading duration: '+ cast(datediff(second,@start_time,@end_time) as nvarchar)+' seconds'
	print' -------------------------------------------------------------------------------'

	set @start_time=GETDATE();
	print '>>truncating table px_cat_g1v2';
	truncate table silver.erp_px_cat_g1v2;
	print '>>inserting data into table px_cat_g1v2';
	insert into silver.erp_px_cat_g1v2(
	id,
	cat,
	subcat,
	maintenance)
	select 
	*
	from bronze.erp_px_cat_g1v2
		set @end_time=GETDATE();
	print 'loading duration: '+ cast(datediff(second,@start_time,@end_time) as nvarchar)+' seconds'
	print' -------------------------------------------------------------------------------'

	set @batch_end_time=GETDATE();
	print' ====================================='
	print 'batch loading duration: '+ cast(datediff(second,@batch_start_time,@batch_end_time) as nvarchar)+' seconds'
	print' ====================================='
	end try
	begin catch
	print '=========================='
	print 'error occured during bronze layer loading'
	print '=========================='
	print 'error message:'+ error_message();
	print 'error num:'+ error_number();
	print 'error severity:'+ error_severity();
	end catch
end
