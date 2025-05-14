function getUdaraJakarta() {
  const today = new Date();
  const lastRunDate = PropertiesService.getScriptProperties().getProperty('lastRunDate');
    
  if (lastRunDate) {
    const lastDate = new Date(lastRunDate);
    const diffInTime = today.getTime() - lastDate.getTime();
    const diffInDays = diffInTime / (1000 * 3600 * 24);
        
    // Use a slightly smaller threshold (1.95 days = 1 day and ~22.8 hours)
    // This gives a ~1.2 hour buffer before the 2-day mark
    if (diffInDays < 1.95) {
      Logger.log("Belum 2 hari, tidak dijalankan.");
      return;
    }
  }
  
  // Ambil data udara dan simpan ke Sheet "Data Udara"
  getUdaraJakartaData();
    
  // Jeda 2 detik (2000 milidetik)
  Utilities.sleep(2000);
  
  // Kirim data dari sheet "Data Udara" via email sebagai CSV
  kirimSheetSebagaiCSV();
  
  // Update waktu terakhir dijalankan
  PropertiesService.getScriptProperties().setProperty('lastRunDate', today.toISOString());
}
