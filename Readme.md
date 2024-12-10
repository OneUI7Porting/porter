# OneUI 7 Porting Guide for Samsung Galaxy S23 Series (QCOM)

**Caution:** This process may require up to **150 GB** of free space on your device for successful ROM porting. Ensure you have enough space available before proceeding.

## Requirements
1. **Download ROMs:**
   - Download the **latest One UI 6 ROM for S23** from SamFirm.
   - Download the **latest One UI 6 ROM for S24** from SamFirm.
   - Download the **S24 UI7 update file** from XDA.

2. **Usage Command:**
   ```bash
   ./gen.sh BASEROM S24UI6BASEROM UI7UPDATEZIP VERSION
   ```

## Features:
- Generates a **64-bit only Vendor**.
- Patched `services.jar` with:
  - Secure Folder fix.
  - Secure Screenshot fix.
- Identifies the device as **Galaxy S23**.

## Compatibility:
- Works for:
  - **Galaxy S23** 
  - **Galaxy S23 Plus**
  - **Galaxy S23 Ultra**
  - Possibly **Galaxy Z Fold 5** and **Galaxy Z Flip 5**.

> **Note:** Be sure to follow the instructions carefully and make sure your device has enough space to avoid issues during the porting process.
