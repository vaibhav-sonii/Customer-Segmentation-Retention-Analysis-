-- Customer Segmentation & Retention Analysis — Database Schema

/* Design notes:
   - Star-schema style: one fact table (orders / transactions) with
     surrogate + natural keys, plus a normalized customer dimension.
   - Customer attributes (Age, City, Signup Date, etc.) are pulled out
     into DIM_CUSTOMERS instead of repeating on every order row — this
     avoids update anomalies (e.g. a customer's city changing) and
     mirrors how a real analytics warehouse would model this data,
     even though the source CSV is flat/denormalized. */

DROP TABLE IF EXISTS fact_orders;
DROP TABLE IF EXISTS dim_customers;

-- Dimension table : one row per unique customer

CREATE TABLE dim_customers (
    customer_id      VARCHAR(10)   PRIMARY KEY,
    gender            VARCHAR(10),
    age               SMALLINT,
    city              VARCHAR(50),
    state             VARCHAR(50),
    region            VARCHAR(20),
    city_tier         SMALLINT,          -- 1 = Metro, 2 = Tier-2, 3 = Tier-3
    signup_date       DATE
);

-- FACT ORDERS: one row per order line

CREATE TABLE fact_orders (
    order_id          VARCHAR(12)   PRIMARY KEY,
    customer_id       VARCHAR(10)   NOT NULL REFERENCES dim_customers(customer_id),
    order_date        DATE          NOT NULL,
    product_category  VARCHAR(50)   NOT NULL,
    quantity          SMALLINT      NOT NULL,
    unit_price        DECIMAL(12,2) NOT NULL,
    discount_percent  SMALLINT      DEFAULT 0,
    discount_amount   DECIMAL(12,2) DEFAULT 0,
    gross_amount      DECIMAL(12,2) NOT NULL,
    net_amount        DECIMAL(12,2) NOT NULL,
    payment_mode      VARCHAR(30),
    order_status      VARCHAR(15)   NOT NULL,   -- Delivered / Returned / Cancelled
    rating            DECIMAL(2,1)              -- NULL if customer did not rate
);

-- Indexes to support the KPI queries below (date range scans, customer
-- rollups, category/region aggregations are the most common access
-- patterns for this workload).

CREATE INDEX idx_orders_customer   ON fact_orders(customer_id);
CREATE INDEX idx_orders_date       ON fact_orders(order_date);
CREATE INDEX idx_orders_status     ON fact_orders(order_status);
CREATE INDEX idx_orders_category   ON fact_orders(product_category);
CREATE INDEX idx_customers_region  ON dim_customers(region);
CREATE INDEX idx_customers_tier    ON dim_customers(city_tier);



























