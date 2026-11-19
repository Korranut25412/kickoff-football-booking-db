-- Example management reports on the KickOff schema (MySQL 8.0+).
-- Run after football_booking.sql:  mysql -u root -p football_booking < reports.sql
USE football_booking;

-- 1) Confirmed revenue by field type, with share of the total
SELECT ft.TypeName,
       COUNT(*)                                            AS confirmed_bookings,
       SUM(b.TotalPrice)                                   AS revenue,
       ROUND(100 * SUM(b.TotalPrice) / SUM(SUM(b.TotalPrice)) OVER (), 1) AS revenue_share_pct
FROM Booking b
JOIN Field f      ON f.FieldID = b.FieldID
JOIN FieldType ft ON ft.FieldTypeID = f.FieldTypeID
WHERE b.BookingStatus = 'ยืนยันแล้ว'
GROUP BY ft.TypeName
ORDER BY revenue DESC;

-- 2) Hours booked per field (excluding cancellations) and status of each field
SELECT f.FieldName, f.FieldStatus,
       ROUND(COALESCE(SUM(TIME_TO_SEC(TIMEDIFF(b.EndTime, b.StartTime))) / 3600, 0), 1) AS hours_booked
FROM Field f
LEFT JOIN Booking b ON b.FieldID = f.FieldID AND b.BookingStatus <> 'ยกเลิก'
GROUP BY f.FieldID, f.FieldName, f.FieldStatus
ORDER BY hours_booked DESC;

-- 3) Payment slips waiting for staff review, oldest first
SELECT p.PaymentID, b.BookingID, CONCAT(c.FirstName, ' ', c.LastName) AS customer,
       p.Amount, p.PaymentMethod, p.PaymentDate,
       TIMESTAMPDIFF(HOUR, p.PaymentDate, '2026-11-02 00:00:00') AS hours_waiting  -- sample "now"
FROM Payment p
JOIN Booking b  ON b.BookingID = p.BookingID
JOIN Customer c ON c.CustomerID = b.CustomerID
WHERE p.PaymentStatus = 'รอตรวจสอบ'
ORDER BY p.PaymentDate;

-- 4) Promotion usage and the discount it gave away (list price reconstructed from TotalPrice)
SELECT pr.PromoCode, pr.DiscountPercent,
       COUNT(b.BookingID)                                                   AS times_used,
       ROUND(SUM(b.TotalPrice * pr.DiscountPercent / (100 - pr.DiscountPercent)), 2) AS discount_given
FROM Promotion pr
LEFT JOIN Booking b ON b.PromotionID = pr.PromotionID AND b.BookingStatus <> 'ยกเลิก'
GROUP BY pr.PromotionID, pr.PromoCode, pr.DiscountPercent;

-- 5) Customer value: bookings, cancellations and confirmed spend
SELECT CONCAT(c.FirstName, ' ', c.LastName) AS customer,
       COUNT(b.BookingID)                                        AS bookings,
       SUM(b.BookingStatus = 'ยกเลิก')                           AS cancelled,
       SUM(CASE WHEN b.BookingStatus = 'ยืนยันแล้ว' THEN b.TotalPrice ELSE 0 END) AS confirmed_spend
FROM Customer c
LEFT JOIN Booking b ON b.CustomerID = c.CustomerID
GROUP BY c.CustomerID, customer
ORDER BY confirmed_spend DESC;
