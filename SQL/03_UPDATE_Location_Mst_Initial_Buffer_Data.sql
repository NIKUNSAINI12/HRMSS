-- ============================================================================
-- CJ DARCL Logistics - Recruitment Architecture (Step 1 Master)
-- File: 03_UPDATE_Location_Mst_Initial_Buffer_Data.sql
-- Purpose: Initialize Base Demand and Buffer % on existing Location_Mst records
-- Created: 2026-09-22
-- ============================================================================

USE [HRBook_22];
GO

-- Update top hubs with approved corridor manpower & buffer
UPDATE dbo.Location_Mst SET BaseDemand = 140, BufferPercent = 10.00, BufferHeads = 14, TargetCapacity = 154 WHERE pk_locid = 'GU-1';   -- Noida
UPDATE dbo.Location_Mst SET BaseDemand = 95,  BufferPercent = 10.00, BufferHeads = 10, TargetCapacity = 105 WHERE pk_locid = 'GU-10';  -- Ahmedabad
UPDATE dbo.Location_Mst SET BaseDemand = 220, BufferPercent = 8.00,  BufferHeads = 18, TargetCapacity = 238 WHERE pk_locid = 'GU-100'; -- Faridabad HO
UPDATE dbo.Location_Mst SET BaseDemand = 75,  BufferPercent = 12.00, BufferHeads = 9,  TargetCapacity = 84  WHERE pk_locid = 'GU-101'; -- Faridabad M&M
UPDATE dbo.Location_Mst SET BaseDemand = 50,  BufferPercent = 5.00,  BufferHeads = 3,  TargetCapacity = 53  WHERE pk_locid = 'GU-102'; -- Faridabad Fleet
UPDATE dbo.Location_Mst SET BaseDemand = 310, BufferPercent = 15.00, BufferHeads = 47, TargetCapacity = 357 WHERE pk_locid = 'GU-146'; -- Bhiwandi
UPDATE dbo.Location_Mst SET BaseDemand = 180, BufferPercent = 10.00, BufferHeads = 18, TargetCapacity = 198 WHERE pk_locid = 'GU-149'; -- Pune Chakan
UPDATE dbo.Location_Mst SET BaseDemand = 110, BufferPercent = 10.00, BufferHeads = 11, TargetCapacity = 121 WHERE pk_locid = 'GU-152'; -- Nagpur
UPDATE dbo.Location_Mst SET BaseDemand = 160, BufferPercent = 10.00, BufferHeads = 16, TargetCapacity = 176 WHERE pk_locid = 'GU-181'; -- Whitefield
UPDATE dbo.Location_Mst SET BaseDemand = 85,  BufferPercent = 10.00, BufferHeads = 9,  TargetCapacity = 94  WHERE pk_locid = 'GU-182'; -- Peenya
UPDATE dbo.Location_Mst SET BaseDemand = 130, BufferPercent = 10.00, BufferHeads = 13, TargetCapacity = 143 WHERE pk_locid = 'GU-201'; -- Chennai Guindy
UPDATE dbo.Location_Mst SET BaseDemand = 90,  BufferPercent = 12.00, BufferHeads = 11, TargetCapacity = 101 WHERE pk_locid = 'GU-205'; -- Sriperumbudur
UPDATE dbo.Location_Mst SET BaseDemand = 140, BufferPercent = 10.00, BufferHeads = 14, TargetCapacity = 154 WHERE pk_locid = 'GU-240'; -- Hyderabad
UPDATE dbo.Location_Mst SET BaseDemand = 200, BufferPercent = 10.00, BufferHeads = 20, TargetCapacity = 220 WHERE pk_locid = 'GU-280'; -- Kolkata
UPDATE dbo.Location_Mst SET BaseDemand = 80,  BufferPercent = 10.00, BufferHeads = 8,  TargetCapacity = 88  WHERE pk_locid = 'GU-310'; -- Jaipur
UPDATE dbo.Location_Mst SET BaseDemand = 115, BufferPercent = 10.00, BufferHeads = 12, TargetCapacity = 127 WHERE pk_locid = 'GU-340'; -- Indore
UPDATE dbo.Location_Mst SET BaseDemand = 95,  BufferPercent = 10.00, BufferHeads = 10, TargetCapacity = 105 WHERE pk_locid = 'GU-410'; -- Ludhiana
UPDATE dbo.Location_Mst SET BaseDemand = 70,  BufferPercent = 8.00,  BufferHeads = 6,  TargetCapacity = 76  WHERE pk_locid = 'GU-490'; -- Kochi
GO
