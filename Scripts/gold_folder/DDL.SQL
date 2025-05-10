/*
===========================================
DDL script-gold views
===========================================
script purpose: create views in 'gold' schema
and drops views with same name if exists,
these views are ready for buisness-use and analytics
===========================================
*/
if OBJECT_ID('gold.dim_customer', 'u') is not null
	drop view gold.dim_customer;
create view gold.dim_customer as
select 
	row_number() over (order by ci.cst_id) as customer_key,
	ci.cst_id as customer_id,
	ci.cst_key as customer_number,
	ci.cst_firstname as first_name,
	ci.cst_lastname as last_name,
	cl.cntry as country,
	ci.cst_marital_status as marital_status,
	case
	when ci.cst_gndr!='N/A' then ci.cst_gndr
		else coalesce(ca.gen,'N/A')
	end as gender,
	ca.bdate as birth_date,
	ci.cst_create_date as create_date
from silver.crm_cust_info ci
left join silver.erp_cust_az12 ca on ca.cid=ci.cst_key
left join silver.erp_loc_a101 cl on cl.cid=ci.cst_key

if OBJECT_ID('gold.dim_product', 'u') is not null
	drop view gold.dim_product;
create view gold.dim_product as
select 
row_number() over (order by pi.prd_start_dt) as product_key,
pi.prd_id as product_id,
pi.prd_key as product_number,
pi.prd_nm as product_name,
pi.cat_id as category_id,
pc.cat as category,
pc.subcat as subcategory,
pi.prs_line as product_line,
pi.prd_cost as product_cost,
pi.prd_start_dt as start_date,
pc.maintenance as maintenance
from silver.crm_prd_info pi
left join silver.erp_px_cat_g1v2 pc on pc.id=pi.cat_id
where pi.prd_end_dt is null --filter all historical data

if OBJECT_ID('gold.fact_sales', 'u') is not null
	drop view gold.fact_sales;
create view gold.fact_sales as
select 
s.sls_ord_num as order_number,
p.product_key as product_key,
c.customer_key as customer_key,
s.sls_price as price,
sls_quantity as quantity,
sls_sales as sales,
sls_order_dt as order_date,
sls_ship_dt as ship_date,
sls_due_dt as due_date
from silver.crm_sales_details s
left join gold.dim_product p on p.product_number=s.sls_prd_key
left join gold.dim_customer c on c.customer_id=s.sls_cust_id
