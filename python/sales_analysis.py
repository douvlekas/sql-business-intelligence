"""
Sales analytics on top of the MySQL e-shop database.

Reads the InvoiceData view with pandas and produces:
  - revenue share per product (pie chart)
  - order value distribution (histogram)
  - daily revenue time series
  - KPIs: total revenue, average order value (AOV), repeat-customer rate

Database credentials are read from environment variables, e.g.:
  export DB_USER=root
  export DB_PASSWORD=your_password

Author: Georgios Douvlekas - MSc Business Mathematics (NKUA & AUEB)
"""

import os

import matplotlib
import mysql.connector
import pandas as pd

matplotlib.use("Agg")  # save charts to files without opening a window
import matplotlib.pyplot as plt  # noqa: E402

os.makedirs("images", exist_ok=True)

db_conn = mysql.connector.connect(
    host=os.getenv("DB_HOST", "localhost"),
    user=os.getenv("DB_USER", "root"),
    password=os.getenv("DB_PASSWORD"),
    database=os.getenv("DB_NAME", "eshop_db"),
)
df = pd.read_sql("SELECT * FROM InvoiceData", db_conn)
db_conn.close()

# 1. Revenue share per product
revenue_by_product = df.groupby("product")["line_total"].sum()
plt.figure(figsize=(8, 8))
revenue_by_product.plot(kind="pie", autopct="%1.1f%%", startangle=140)
plt.title("Revenue Share per Product")
plt.ylabel("")
plt.savefig("images/pie_chart.png", dpi=150)
plt.close()

# 2. Order value distribution
order_totals = df.groupby("order_id")["line_total"].sum()
plt.figure(figsize=(10, 6))
plt.hist(order_totals, bins=5, color="teal", edgecolor="white")
plt.title("Order Value Distribution")
plt.xlabel("Order amount (EUR)")
plt.ylabel("Frequency")
plt.savefig("images/histogram.png", dpi=150)
plt.close()

# 3. Daily revenue time series
df["order_date"] = pd.to_datetime(df["order_date"])
daily_sales = df.groupby(df["order_date"].dt.date)["line_total"].sum()

plt.figure(figsize=(12, 6))
daily_sales.plot(kind="line", marker="o", color="darkgreen", linewidth=2)
plt.title("Daily Sales Revenue", fontsize=14)
plt.xlabel("Date")
plt.ylabel("Revenue (EUR)")
plt.grid(True, linestyle="--", alpha=0.6)
plt.savefig("images/time_series.png", dpi=150)
plt.close()

# 4. KPIs
average_basket = order_totals.mean()

orders_per_customer = df.groupby("customer")["order_id"].nunique()
total_customers = len(orders_per_customer)
repeat_customers = int((orders_per_customer > 1).sum())
repeat_rate = repeat_customers / total_customers * 100

print("KEY PERFORMANCE INDICATORS")
print(f"Total revenue:              {order_totals.sum():.2f} EUR")
print(f"Average order value (AOV):  {average_basket:.2f} EUR")
print(f"Repeat-customer rate:       {repeat_rate:.1f}% ({repeat_customers} of {total_customers} customers)")
