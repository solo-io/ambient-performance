from __future__ import print_function

import csv
import datetime
import os.path
import pygsheets

SOURCE_SPREADSHEET_ID = "1gPMSjKMYU9HUlueS9HgiEZ2kqBta5X6JA9E4LvdXMWQ"
CREDENTIALS_FILE = "/home/daniel/Downloads/client_secert.json"

gc = pygsheets.authorize(client_secret=CREDENTIALS_FILE, local=True)


def read_and_replace(worksheet, file):
    with open(file, "r") as f:
        reader = csv.reader(f, skipinitialspace=True, delimiter=',', quotechar='"')
        data = list(reader)
    worksheet.update_values(crange='A1', values=data)


# Clone the source sheet, and grab the worksheets for the tests so we can replace them with the new data.
new_spreadsheet = gc.create("Performance Results " + datetime.datetime.now().strftime("%m/%d/%Y, %H:%M:%S"), template=SOURCE_SPREADSHEET_ID)
sheettcp = new_spreadsheet.worksheet_by_title('data')

csvfile = os.environ['RESULTS']

# I don't like hard coding these, but this is the quickest way.
read_and_replace(sheettcp, csvfile)

print("New spreadsheet is ready at https://docs.google.com/spreadsheets/d/" + new_spreadsheet.id + "/edit#gid=0")
