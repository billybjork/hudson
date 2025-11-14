/**
 * Google Apps Script: Extract Product Images and Data from Sheet
 *
 * USAGE:
 * 1. Open your Google Sheet
 * 2. Go to Extensions → Apps Script
 * 3. Delete any existing code
 * 4. Paste this entire script
 * 5. Save (Ctrl+S / Cmd+S)
 * 6. Run the function: extractImagesAndData
 * 7. Grant permissions when prompted
 * 8. Check your Google Drive for the generated folder
 *
 * OUTPUT:
 * Creates a folder in your Drive with:
 * - products.json (product data)
 * - images/ folder (extracted product images)
 */

function extractImagesAndData() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getActiveSheet();

  // Get all data from sheet
  const dataRange = sheet.getDataRange();
  const values = dataRange.getValues();

  // Find column indices from header row
  const headers = values[0];
  const colMap = {
    pic: headers.indexOf('PIC'),
    details: headers.indexOf('DETAILS/TALKING POINTS'),
    originalPrice: headers.indexOf('ORIGINAL PRICE'),
    salePrice: headers.indexOf('SALE PRICE'),
    pid: headers.indexOf('PID'),
    sku: headers.indexOf('PAVOI SKU')
  };

  // Verify required columns exist
  const requiredCols = ['pic', 'details', 'originalPrice', 'salePrice', 'pid', 'sku'];
  for (const col of requiredCols) {
    if (colMap[col] === -1) {
      throw new Error(`Column not found: ${col}. Please check your header row.`);
    }
  }

  // Create output folder
  const sheetName = sheet.getName();
  const timestamp = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-dd-HHmmss');
  const folderName = `Hudson_Import_${sheetName}_${timestamp}`;
  const outputFolder = DriveApp.createFolder(folderName);
  const imagesFolder = outputFolder.createFolder('images');

  Logger.log(`Created folder: ${folderName}`);
  Logger.log(`Folder URL: ${outputFolder.getUrl()}`);

  const products = [];

  // Process each row (skip header)
  for (let i = 1; i < values.length; i++) {
    const row = values[i];

    // Skip empty rows (check for required name field)
    const name = extractName(row[colMap.details]);
    if (!name) continue;

    // Extract and save image
    let imageFilename = null;
    try {
      const imageBlob = extractImageFromCell(sheet, i + 1, colMap.pic + 1); // +1 for 1-indexed
      if (imageBlob) {
        // Use PID for image filename if available, otherwise use row index
        const pid = String(row[colMap.pid] || '').trim();
        imageFilename = pid ? `${pid}.jpg` : `${i}.jpg`;
        const imageFile = imagesFolder.createFile(imageBlob.setName(imageFilename));
        Logger.log(`Saved image: ${imageFilename}`);
      }
    } catch (e) {
      Logger.log(`Warning: Could not extract image for product: ${e.message}`);
    }

    // Parse prices
    const originalPrice = parsePrice(row[colMap.originalPrice]);
    const salePrice = parsePrice(row[colMap.salePrice]);

    // Build product object
    const product = {
      name: name,
      talking_points_md: formatTalkingPoints(row[colMap.details]),
      original_price_cents: originalPrice,
      sale_price_cents: salePrice,
      pid: String(row[colMap.pid] || '').trim(),
      sku: String(row[colMap.sku] || '').trim(),
      image_filename: imageFilename
    };

    products.push(product);
    Logger.log(`Processed product: ${product.name}`);
  }

  // Save products.json
  const jsonContent = JSON.stringify({
    sheet_name: sheetName,
    exported_at: new Date().toISOString(),
    products: products
  }, null, 2);

  outputFolder.createFile('products.json', jsonContent, MimeType.PLAIN_TEXT);

  // Create README
  const readmeContent = `Hudson Product Import
Generated: ${new Date().toISOString()}
Source Sheet: ${sheetName}
Total Products: ${products.length}

To import these products:
1. Download this folder
2. Extract to your Hudson project: priv/import/${folderName}/
3. Run: mix run priv/import/import_products.exs priv/import/${folderName}

Files:
- products.json: Product data
- images/: Product images (${products.filter(p => p.image_filename).length} images)
`;

  outputFolder.createFile('README.txt', readmeContent, MimeType.PLAIN_TEXT);

  // Show completion dialog
  const ui = SpreadsheetApp.getUi();
  ui.alert(
    'Export Complete!',
    `Exported ${products.length} products.\n\n` +
    `Folder: ${folderName}\n` +
    `Location: ${outputFolder.getUrl()}\n\n` +
    `Click OK to open the folder.`,
    ui.ButtonSet.OK
  );

  Logger.log(`Export complete! ${products.length} products exported.`);
  Logger.log(`Open folder: ${outputFolder.getUrl()}`);
}

/**
 * Extract image from a cell
 */
function extractImageFromCell(sheet, row, col) {
  try {
    // Get the formula (images are stored as IMAGE() formulas)
    const formula = sheet.getRange(row, col).getFormula();

    if (formula && formula.startsWith('=IMAGE(')) {
      // Extract URL from formula: =IMAGE("https://...")
      const urlMatch = formula.match(/IMAGE\("([^"]+)"\)/);
      if (urlMatch) {
        const url = urlMatch[1];
        const response = UrlFetchApp.fetch(url);
        return response.getBlob();
      }
    }

    // Try to get image directly from cell drawings
    const images = sheet.getImages();
    for (const image of images) {
      const anchorRow = image.getAnchorRow();
      const anchorCol = image.getAnchorColumn();

      if (anchorRow === row && anchorCol === col) {
        const url = image.getUrl();
        if (url) {
          const response = UrlFetchApp.fetch(url);
          return response.getBlob();
        }
      }
    }

    return null;
  } catch (e) {
    Logger.log(`Error extracting image from R${row}C${col}: ${e.message}`);
    return null;
  }
}

/**
 * Parse price string to cents
 * Handles formats: "$49.95", "12.95-23.95", "45.00"
 */
function parsePrice(priceStr) {
  if (!priceStr) return null;

  const str = String(priceStr).trim();

  // Handle range (take first price)
  if (str.includes('-')) {
    const parts = str.split('-');
    priceStr = parts[0].trim();
  }

  // Remove $ and convert to cents
  const cleaned = String(priceStr).replace(/[$,]/g, '').trim();
  const dollars = parseFloat(cleaned);

  if (isNaN(dollars)) return null;

  return Math.round(dollars * 100);
}

/**
 * Extract product name from details text
 * Name is typically the first line
 */
function extractName(detailsText) {
  if (!detailsText) return 'Unnamed Product';

  const lines = String(detailsText).split('\n');
  const firstLine = lines[0].trim();

  // Remove common prefixes
  return firstLine
    .replace(/^TIKTOK EXCLUSIVE BUNDLE\s*/i, '')
    .replace(/^Selling Point:\s*/i, '')
    .trim();
}

/**
 * Format talking points as markdown
 */
function formatTalkingPoints(detailsText) {
  if (!detailsText) return '';

  const text = String(detailsText);

  // Convert to markdown bullet points
  const lines = text.split('\n');
  const formatted = lines
    .map(line => line.trim())
    .filter(line => line.length > 0)
    .map(line => {
      // If line starts with -, keep it
      if (line.startsWith('-')) return line;
      // Otherwise add bullet
      return `- ${line}`;
    })
    .join('\n');

  return formatted;
}
