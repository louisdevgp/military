// Client-side declaration of the SENRAISE SRPrinter binder interface
// (service recieptservice.com.recieptservice/.service.PrinterService, observed
// on the H10 with SRPrinter 8.3.5). Written for this project from the method
// signatures documented publicly; no vendor code is bundled.
//
// Binder transaction codes follow declaration order: never reorder, insert or
// remove methods above the last one used. Later service methods are omitted.
// Compatibility is only established by a physical print test (docs/recette.md).
package recieptservice.com.recieptservice;

import android.graphics.Bitmap;

interface PrinterInterface {
    void printEpson(in byte[] data);
    String getServiceVersion();
    void printText(String text);
    void printBitmap(in Bitmap pic);
    void printBarCode(String data, int symbology, int height, int width);
    void printQRCode(String data, int modulesize, int errorlevel);
    void setAlignment(int alignment);
    void setTextSize(float textSize);
    void nextLine(int line);
    void printTableText(in String[] text, in int[] weight, in int[] alignment);
    void setTextBold(boolean bold);
    void beginWork();
    void endWork();
}
