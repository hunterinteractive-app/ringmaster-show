from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.utils import ImageReader

root = Path(__file__).resolve().parents[2]
pdfmetrics.registerFont(TTFont('Noto', str(root/'assets/fonts/NotoSans-Regular.ttf')))
pdfmetrics.registerFont(TTFont('NotoBold', str(root/'assets/fonts/NotoSans-Bold.ttf')))
pdfmetrics.registerFontFamily('Noto',normal='Noto',bold='NotoBold')
PURPLE=colors.HexColor('#392277'); INK=colors.HexColor('#202A44'); MUTED=colors.HexColor('#50596A'); TEAL=colors.HexColor('#4EA3AF'); PALE=colors.HexColor('#F1EEF8'); GOLD=colors.HexColor('#FACB2E')
W,H=612,792; M=42; CW=W-2*M
out=root/'output/pdf/RingMaster-Show-Check-In-Quick-Guide.pdf'
out.parent.mkdir(parents=True, exist_ok=True)
c=canvas.Canvas(str(out), pagesize=(W,H))
c.setTitle('RingMaster Show - Check-In Quick Guide'); c.setAuthor('RingMaster Show')
style=ParagraphStyle('body',fontName='Noto',fontSize=10,leading=14,textColor=INK)
small=ParagraphStyle('small',parent=style,fontSize=9,leading=12.5)
y=0

def para(text, x=M, width=CW, size=None, gap=8):
    global y
    p=Paragraph(text, size or style); _,h=p.wrap(width,H);p.drawOn(c,x,y-h); y-=h+gap

def heading(text):
    global y
    y-=4
    para(text,size=ParagraphStyle('h',parent=style,fontName='NotoBold',fontSize=14,leading=18,textColor=PURPLE),gap=9)

def step(n,title,body):
    global y
    c.setFillColor(PURPLE);c.circle(M+10,y-10,10,fill=1,stroke=0)
    c.setFillColor(colors.white);c.setFont('NotoBold',10);c.drawCentredString(M+10,y-13.5,str(n))
    para('<b>'+title+'</b><br/>'+body,x=M+30,width=CW-30,gap=12)

def box(title,body):
    global y
    p=Paragraph('<b>'+title+'</b><br/>'+body,small);_,h=p.wrap(CW-24,H)
    c.setFillColor(PALE);c.roundRect(M,y-h-24,CW,h+24,8,fill=1,stroke=0)
    p.drawOn(c,M+12,y-12-h);y-=h+36

def header(kicker,title,page):
    global y
    c.setFillColor(PURPLE);c.rect(0,H-111,W,111,fill=1,stroke=0)
    c.setFillColor(GOLD);c.rect(M,H-32,34,4,fill=1,stroke=0)
    c.setFillColor(colors.white);c.setFont('NotoBold',10);c.drawString(M,H-49,'RINGMASTER SHOW  /  '+kicker.upper())
    c.setFont('NotoBold',24);c.drawString(M,H-84,title)
    c.setStrokeColor(colors.HexColor('#D6D9E0'));c.line(M,43,W-M,43)
    c.setFillColor(MUTED);c.setFont('Noto',8);c.drawString(M,29,'Check-In Quick Guide  |  November 2026')
    c.drawRightString(W-M,29,f'{page} / 2')
    y=H-132

header('For show secretaries','Set up exhibitor check-in',1)
para('Let exhibitors review their entries, request permitted corrections, and confirm their check-in from a show-specific QR code or link.')
step(1,'Open Check-In Settings','From your show, open <b>Show Settings &gt; Check-In Settings</b>. Show owners, assigned show secretaries, and super administrators can configure this feature. Locked or finalized shows are view-only.')
step(2,'Enable the portal and set its availability','Turn on <b>Enable Exhibitor Check-In Portal</b>. Set <b>Opens</b> and <b>Closes</b> as needed. Times use the current time zone on your device. A blank time means no limit at that end of the window.')
step(3,'Choose the confirmation requirements','Optionally require digital initials and a typed signature. Every exhibitor must confirm that their entries are correct before completing check-in.')
step(4,'Decide which changes exhibitors may make','Choose a permission for each action: ear number, breed, variety, class, sex, fur variety, scratching an entry, or adding an entry.')
# Compact permission reference, no dense technical setup.
for title,body in [
('Disabled','The exhibitor must contact staff for this change.'),
('Allowed automatically','An eligible request is applied without secretary approval.'),
('Secretary approval required','The request waits for staff review before it is applied.')]:
    para('<b>'+title+':</b> '+body,x=M+30,width=CW-30,size=small,gap=5)
y-=5
step(5,'Review action fees and save','Set any fees for completed changes. <b>Add Entry</b> uses the normal show entry fee unless you choose a custom amount. Fees are added to the exhibitor balance. Exhibitors without a linked account need staff help with fee-bearing changes. Select <b>Save Settings</b>.')
step(6,'Generate and share the show link','Select <b>Generate New QR Code</b>, then <b>Copy Link</b>. Save the link and QR image before closing the dialog. Share the link with exhibitors or print the QR code for the check-in desk.')
box('Keep the same QR code once it is shared','Generating another QR code immediately invalidates the earlier link. Do not regenerate it just to reopen the portal or change its availability. Save setting changes instead.')
assert y>48, y
c.showPage()
header('Show-day reference','Check in and follow up',2)
heading('What exhibitors do')
step(1,'Open the show link or scan its QR code','Use the link for the correct show during its check-in window. Enter the exhibitor number and last name recorded on the entry, then select <b>Continue</b>. A RingMaster login is not needed for this verification.')
step(2,'Review each entry','Check the show section, ear number, breed, variety, class, and sex. Select <b>Request change</b> for an entry if a correction is needed. Available actions follow the show settings. Requests requiring approval stay pending until staff reviews them.')
step(3,'Confirm and complete','After resolving discrepancies, check <b>I confirm these entries are correct</b>. Enter initials and your full name if required, choose a receipt preference, then select <b>Complete Check-In</b>. Look for <b>Check-In Complete</b>.')
box('Check-in and payment are separate','Check-in confirms the entries; it does not clear a balance or automatically charge a card. Exhibitors should review Payment status and follow the show\'s payment instructions. Staff should check balances separately.')
heading('What staff do')
para('Open <b>Show Settings &gt; Admin Operations (Pre-show) &gt; Check-In Dashboard</b>. With the portal enabled, staff can use the dashboard before, during, and after the exhibitor check-in window.',gap=9)
for title,body in [
('Check-In Roster','Find an exhibitor and review their check-in status.'),
('Check-In Change Requests','Review pending corrections; approve or reject them as appropriate. Confirm the result before finalizing the exhibitor\'s check-in.'),
('Complete Check-In','Help exhibitors who cannot use the portal. Select the exhibitor, review their entries, and complete the staff confirmation.'),
('Balances and payments','Use <b>Exhibitors with a balance due</b> to follow up. Use <b>Record Payment</b> only for money actually received outside the online checkout.'),
('Review and refresh','Use <b>Mark reviewed</b> after staff review. Use <b>Lock check-in</b> when confirmation should be closed to further exhibitor changes. Refresh the dashboard for the latest counts; use <b>Check-In Activity</b> to review actions.')]:
    para('<b>'+title+':</b> '+body,size=small,gap=7)
heading('If an exhibitor cannot continue')
para('Check the show link, opening and closing times, exhibitor number, and last name. Verify each family member under their own exhibitor record. If a session expires, open the link and verify again. If the issue remains, have staff assist through the dashboard.',size=small,gap=0)
assert y>48,y
c.save()
print(out)
