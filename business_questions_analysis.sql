-- Q1. Monthly Revenue, Orders & Average Order Value (Aggregation)
-- Business question: How is revenue trending month over month?

SELECT
    TO_CHAR(order_date, 'YYYY-MM')  AS order_month,
    COUNT(DISTINCT order_id)        AS total_orders,
    ROUND(SUM(net_amount), 2)       AS net_revenue,
    ROUND(SUM(net_amount) * 1.0 / COUNT(DISTINCT order_id), 2) AS avg_order_value
FROM fact_orders
WHERE order_status = 'Delivered'
GROUP BY 1
ORDER BY 1;

-- Q2. Revenue Contribution % by Product Category (Window Function)
-- Business question: Which categories drive the most revenue?

SELECT
    product_category,
    ROUND(SUM(net_amount), 2) AS category_revenue,
    ROUND(100.0 * SUM(net_amount) / SUM(SUM(net_amount)) OVER (), 2) AS pct_of_total_revenue
FROM fact_orders
WHERE order_status = 'Delivered'
GROUP BY product_category
ORDER BY category_revenue DESC;

-- Q3. Top 10 Customers by Lifetime Revenue (Ranking + Join)
-- Business question: Who are our most valuable customers?

SELECT
    c.customer_id, c.city, c.region,
    ROUND(SUM(o.net_amount), 2) AS lifetime_revenue,
    RANK() OVER (ORDER BY SUM(o.net_amount) DESC) AS revenue_rank
FROM fact_orders o
JOIN dim_customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'Delivered'
GROUP BY c.customer_id, c.city, c.region
ORDER BY lifetime_revenue DESC
LIMIT 10;

-- Q4. RFM Base Table (CTE + Window Functions)
-- Business question: What is each customer's Recency/Frequency/Monetary profile?

WITH last_order AS (
    SELECT customer_id, MAX(order_date) AS last_purchase_date
    FROM fact_orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_id
),
rfm_base AS (
    SELECT
        o.customer_id,
        COUNT(DISTINCT o.order_id)                AS frequency,
        ROUND(SUM(o.net_amount), 2)               AS monetary,
        (SELECT MAX(order_date)::DATE FROM fact_orders) -
		lo.last_purchase_date::DATE AS recency_days
    FROM fact_orders o
    JOIN last_order lo ON lo.customer_id = o.customer_id
    WHERE o.order_status = 'Delivered'
    GROUP BY o.customer_id, lo.last_purchase_date
)
SELECT
    customer_id, recency_days, frequency, monetary,
    NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,   -- most recent = highest score
    NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
    NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score
FROM rfm_base
ORDER BY monetary DESC;

-- Q5. Repeat vs One-Time Customers (Subquery + CASE)
-- Business question: What share of customers are repeat buyers?

SELECT
    CASE WHEN order_count > 1 THEN 'Repeat Customer' ELSE 'One-Time Customer' END AS customer_type,
    COUNT(*) AS num_customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_customers
FROM (
    SELECT customer_id, COUNT(DISTINCT order_id) AS order_count
    FROM fact_orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_id
) t
GROUP BY customer_type;


-- Q6. Month-over-Month Revenue Growth % (Window Function: LAG)
-- Business question: Which months grew or declined vs the previous month?

WITH monthly AS (
    SELECT
    TO_CHAR(order_date, 'YYYY-MM') AS order_month,
           SUM(net_amount) AS net_revenue
    FROM fact_orders
    WHERE order_status = 'Delivered'
    GROUP BY 1
)
SELECT
    order_month,
    net_revenue,
    LAG(net_revenue) OVER (ORDER BY order_month) AS prev_month_revenue,
    ROUND(100.0 * (net_revenue - LAG(net_revenue) OVER (ORDER BY order_month))
          / LAG(net_revenue) OVER (ORDER BY order_month), 2) AS mom_growth_pct
FROM monthly
ORDER BY order_month;


-- Q7. Monthly Cohort Retention (Self-Join + CTE)
-- Business question: Of customers who first purchased in month X, how many
-- were still active in month X+1, X+2, etc.?

WITH first_purchase AS (
    SELECT customer_id, MIN(TO_CHAR(order_date, 'YYYY-MM')) AS cohort_month
    FROM fact_orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_id
),
activity AS (
    SELECT o.customer_id, fp.cohort_month, TO_CHAR(o.order_date, 'YYYY-MM') AS activity_month
    FROM fact_orders o
    JOIN first_purchase fp ON fp.customer_id = o.customer_id
    WHERE o.order_status = 'Delivered'
)
SELECT
    cohort_month,
    activity_month,
    (EXTRACT(YEAR FROM TO_DATE(activity_month, 'YYYY-MM')) - EXTRACT(YEAR FROM TO_DATE(cohort_month, 'YYYY-MM'))) * 12 + 
    (EXTRACT(MONTH FROM TO_DATE(activity_month, 'YYYY-MM')) - EXTRACT(MONTH FROM TO_DATE(cohort_month, 'YYYY-MM'))) AS month_index,
    COUNT(DISTINCT customer_id) AS active_customers
FROM activity
GROUP BY cohort_month, activity_month
ORDER BY cohort_month, activity_month;

-- Q8. At-Risk / Churned Customers — No Order in Last 180 Days (Subquery)
-- Business question: Which customers should receive win-back/loyalty offers?

SELECT
    c.customer_id, c.city, c.region,
    (SELECT MAX(order_date) FROM fact_orders o
      WHERE o.customer_id = c.customer_id AND o.order_status = 'Delivered') AS last_purchase_date,
    (SELECT ROUND(SUM(net_amount), 2) FROM fact_orders o
      WHERE o.customer_id = c.customer_id AND o.order_status = 'Delivered') AS lifetime_revenue
FROM dim_customers c
WHERE c.customer_id IN (
    SELECT customer_id FROM fact_orders WHERE order_status = 'Delivered' GROUP BY customer_id
)
AND (SELECT MAX(order_date)::DATE FROM fact_orders) - 
    (SELECT MAX(order_date)::DATE FROM fact_orders o
     WHERE o.customer_id = c.customer_id AND o.order_status = 'Delivered') > 180
ORDER BY lifetime_revenue DESC;

-- Q9. Top-Selling Product Category per Region (Window Function: RANK, Partition By)
-- Business question: Which category leads in each region — for regional marketing plans?

WITH region_category_revenue AS (
    SELECT c.region, o.product_category, SUM(o.net_amount) AS revenue
    FROM fact_orders o
    JOIN dim_customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'Delivered'
    GROUP BY c.region, o.product_category
)
SELECT region, product_category, ROUND(revenue, 2) AS revenue, category_rank
FROM (
    SELECT *, RANK() OVER (PARTITION BY region ORDER BY revenue DESC) AS category_rank
    FROM region_category_revenue
) ranked
WHERE category_rank = 1
ORDER BY revenue DESC;

-- Q10. Running Total (Cumulative) Revenue by Month (Window Function)
-- Business question: What is our cumulative revenue trajectory this year?

WITH monthly AS (
    SELECT TO_CHAR(order_date, 'YYYY-MM') AS order_month, SUM(net_amount) AS net_revenue
    FROM fact_orders
    WHERE order_status = 'Delivered'
    GROUP BY 1
)
SELECT
    order_month, net_revenue,
    ROUND(SUM(net_revenue) OVER (ORDER BY order_month), 2) AS running_total_revenue
FROM monthly
ORDER BY order_month;

-- Q11. Return & Cancellation Rate by Product Category (Aggregation + CASE)
-- Business question: Which categories have quality/fit issues driving returns?

SELECT
    product_category,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN order_status = 'Returned' THEN 1 ELSE 0 END)     AS returned_orders,
    SUM(CASE WHEN order_status = 'Cancelled' THEN 1 ELSE 0 END)    AS cancelled_orders,
    ROUND(100.0 * SUM(CASE WHEN order_status IN ('Returned','Cancelled') THEN 1 ELSE 0 END)
          / COUNT(*), 2) AS return_cancel_rate_pct
FROM fact_orders
GROUP BY product_category
ORDER BY return_cancel_rate_pct DESC;
