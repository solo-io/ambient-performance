from __future__ import print_function

import csv
import datetime
import os.path
import pygsheets

SOURCE_SPREADSHEET_ID = "1pAY_nQH51rpLHpjJo8O3K84G6GDnpZWExp37mvjp58U"
CREDENTIALS_FILE = "/home/daniel/Downloads/client_secert.json"

gc = pygsheets.authorize(client_secret=CREDENTIALS_FILE, local=True)


def read_and_replace(worksheet, file):
    with open(file, "r") as f:
        reader = csv.reader(f, skipinitialspace=True, delimiter=',', quotechar='"')
        data = list(reader)
    worksheet.update_values(crange='A1', values=data)


# Clone the source sheet, and grab the worksheets for the tests so we can replace them with the new data.
new_spreadsheet = gc.create("Performance Results " + datetime.datetime.now().strftime("%m/%d/%Y, %H:%M:%S"), template=SOURCE_SPREADSHEET_ID)
sheet1 = new_spreadsheet.worksheet_by_title('1')
sheet2 = new_spreadsheet.worksheet_by_title('2')
sheet8 = new_spreadsheet.worksheet_by_title('8')
sheet16 = new_spreadsheet.worksheet_by_title('16')
sheet32 = new_spreadsheet.worksheet_by_title('32')
sheet64 = new_spreadsheet.worksheet_by_title('64')
sheet128 = new_spreadsheet.worksheet_by_title('128')

csv_dir = os.environ['RESULTS_DIRECTORY']

# I don't like hard coding these, but this is the quickest way.
read_and_replace(sheet1, os.path.join(csv_dir, "1.csv"))
read_and_replace(sheet2, os.path.join(csv_dir, "2.csv"))
read_and_replace(sheet8, os.path.join(csv_dir, "8.csv"))
read_and_replace(sheet16, os.path.join(csv_dir, "16.csv"))
read_and_replace(sheet32, os.path.join(csv_dir, "32.csv"))
read_and_replace(sheet64, os.path.join(csv_dir, "64.csv"))
read_and_replace(sheet128, os.path.join(csv_dir, "128.csv"))

print("New spreadsheet is ready at https://docs.google.com/spreadsheets/d/" + new_spreadsheet.id + "/edit#gid=0")
