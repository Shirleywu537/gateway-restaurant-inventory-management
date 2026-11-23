from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from pathlib import Path
import subprocess,os
root=Path(__file__).resolve().parent.parent
out=root/'dist/examples';out.mkdir(exist_ok=True)
p=out/'sample-invoice.pdf'
c=canvas.Canvas(str(p),pagesize=(612,792));c.setTitle('Fictional Metro Produce Invoice')
c.setFillColor(HexColor('#214d3d'));c.rect(0,672,612,120,fill=1,stroke=0);c.setFillColorRGB(1,1,1);c.setFont('Helvetica-Bold',26);c.drawString(44,731,'METRO PRODUCE');c.setFont('Helvetica',13);c.drawString(44,701,'Fictional supplier invoice - software demo only')
c.setFillColor(HexColor('#20352e'));c.setFont('Helvetica-Bold',20);c.drawString(44,622,'INVOICE');c.setFont('Helvetica',12)
for i,t in enumerate(['Invoice number: DEMO-INV-2026-001','Purchase order: DEMO-PO-001','Invoice date: November 16, 2026','Bill to: Demo Restaurant NYC']):c.drawString(44,591-i*24,t)
c.setFillColor(HexColor('#e8efe4'));c.rect(44,430,524,34,fill=1,stroke=0);c.setFillColor(HexColor('#20352e'));c.setFont('Helvetica-Bold',11)
for x,t in [(54,'DESCRIPTION'),(300,'QUANTITY'),(405,'UNIT PRICE'),(510,'AMOUNT')]:c.drawString(x,442,t)
c.setFont('Helvetica',12)
for x,t in [(54,'Tomatoes'),(300,'3 kg'),(420,'$2.50'),(520,'$7.50')]:c.drawString(x,405,t)
c.setStrokeColor(HexColor('#dbe2d6'));c.line(44,386,568,386);c.setFont('Helvetica-Bold',13);c.drawString(405,352,'Total USD');c.drawString(520,352,'$7.50')
c.setFont('Helvetica',11);c.drawString(44,278,'This invoice covers the tomatoes in this delivery only.');c.drawString(44,257,'Check the actual delivery before recording any stock.');c.drawString(44,236,'Tax, payment, and accounting are outside this sample.');c.setFont('Helvetica',10);c.drawString(44,78,'FICTIONAL DATA - Not a commercial invoice.');c.save()
preview=root/'artifacts/2026-11-16/sample-invoice'
preview.parent.mkdir(parents=True,exist_ok=True)
fontconfig=preview.parent/'fontconfig.xml'
fontconfig.write_text('<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><dir>/System/Library/Fonts</dir><dir>/usr/share/fonts</dir><cachedir>/private/tmp/gateway-font-cache</cachedir></fontconfig>')
env=dict(os.environ,FONTCONFIG_FILE=str(fontconfig),XDG_CACHE_HOME='/private/tmp/gateway-font-cache')
subprocess.run(['pdftoppm','-r','180','-singlefile','-png',str(p),str(preview)],check=True,env=env,capture_output=True,timeout=45)
c=canvas.Canvas(str(out/'sample-invoice-scan.pdf'),pagesize=(612,792));c.drawImage(str(preview)+'.png',0,0,width=612,height=792);c.save()
print('Created text and image-only PDF test invoices.')
