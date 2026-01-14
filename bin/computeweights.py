# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "pandas",
#     "requests",
#     "xmltodict",
#     "pyyaml",
# ]
# ///
import argparse
import requests
import xmltodict
import glob
import yaml
import pandas as pd

# obtain svbenchpath and tag from argparse
parser = argparse.ArgumentParser()
parser.add_argument("--svbenchpath", default="/home/goblint/sv-benchmarks", help="Path to the sv-benchmarks directory")
parser.add_argument("--tag", default="svcomp26-rc.1", help="Git tag or branch to download goblint.xml from")
parser.add_argument("--xml", default=None, help="Path to local XML file instead of downloading from GitLab")
parser.add_argument("--outcsv", default="weightstable.csv", help="Path to output CSV file")
args = parser.parse_args()

tag = args.tag
url = f"https://gitlab.com/sosy-lab/sv-comp/bench-defs/-/raw/{tag}/benchmark-defs/goblint.xml"
svbenchpath = args.svbenchpath
response = requests.get(url)

df = []
goblint=xmltodict.parse(response.content)

if args.xml:
    with open(args.xml, 'r') as f:
        filecontent=f.read()
    goblint=xmltodict.parse(filecontent)
definitions=goblint["benchmark"]["rundefinition"]
for definition in definitions:
    name=definition["@name"]
    print("Definition:", name)
    tasks=definition["tasks"]
    if not isinstance(tasks, list):
        tasks=[tasks]
    for task in tasks:
        taskname=task["@name"]
        propertyfile=task["propertyfile"]
        # basename of propertyfile without extension
        propertyfile=propertyfile.split("/")[-1].split(".")[0]
        includesfile=task["includesfile"]
        if not isinstance(includesfile, list):
            includesfile= [includesfile]
        for include in includesfile:
            # setfilename is the svbenchpath + include
            include=svbenchpath + "/" + include
            #if file does not exist, skip
            try:
                open(include, 'r')
            except FileNotFoundError:
                print(f"Include file {include} not found, skipping.")
                continue
            #open and read the include file
            with open(include, 'r') as f:
                content=f.read()
                for line in content.splitlines():
                    # ignore comments and empty lines
                    line=line.strip()
                    if line.startswith("#") or line == "":
                        continue
                    paths = glob.glob(svbenchpath + "/c/" + line)
                    for path in paths:
                        # open ayml file in path and read the content
                        with open(path, 'r') as f:
                            yamlcontent=yaml.safe_load(f)
                        props=yamlcontent["properties"]
                        for prop in props:
                            propfil=prop["property_file"].split("/")[-1].split(".")[0]
                            if propfil != propertyfile:
                                continue
                            # skip if expected_verdict is not a key in prop
                            if "expected_verdict" not in prop:
                                continue
                            verdict=prop["expected_verdict"]
                            # remove svbenchpath + "/c/" from path
                            path=path.replace(svbenchpath + "/c/", "")
                            #print(f"{propertyfile},{taskname},{path},{verdict}")
                            # collect the lines for this propertyfile and taskname and path in a pd frame
                            df.append({"category": taskname, "property": propertyfile, "ymlfile": path, "expected": verdict})
        if "excludesfile" in task:
            excludesfile=task["excludesfile"]
        else:
            excludesfile = []
        if not isinstance(excludesfile, list):
            excludesfile= [excludesfile]
        for exclude in excludesfile:
            # setfilename is the svbenchpath + exclude
            exclude=svbenchpath + "/" + exclude
            #if file does not exist, skip
            try:
                open(exclude, 'r')
            except FileNotFoundError:
                print(f"Exclude file {exclude} not found, skipping.")
                continue
            #open and read the exclude file
            with open(exclude, 'r') as f:
                content=f.read()
                for line in content.splitlines():
                    # ignore comments and empty lines
                    line=line.strip()
                    if line.startswith("#") or line == "":
                        continue
                    paths = glob.glob(svbenchpath + "/c/" + line)
                    for path in paths:
                        # open ayml file in path and read the content
                        with open(path, 'r') as f:
                            yamlcontent=yaml.safe_load(f)
                        props=yamlcontent["properties"]
                        for prop in props:
                            propfil=prop["property_file"].split("/")[-1].split(".")[0]
                            if propfil != propertyfile:
                                continue
                            # skip if expected_verdict is not a key in prop
                            if "expected_verdict" not in prop:
                                continue
                            verdict=prop["expected_verdict"]
                            # remove svbenchpath + "/c/" from path
                            path=path.replace(svbenchpath + "/c/", "")
                            #print(f"{propertyfile},{taskname},{path},{verdict}")
                            # collect the lines for this propertyfile and taskname and path in a pd frame
                            df.remove({"category": taskname, "property": propertyfile, "ymlfile": path, "expected": verdict})
    print("Done")
df=pd.DataFrame(df)


###############################################################
#df = pd.read_csv("category_yml.csv")

categories_url = f"https://gitlab.com/sosy-lab/sv-comp/bench-defs/-/raw/{tag}/benchmark-defs/category-structure.yml"
categories_response = requests.get(categories_url)
categories_data=yaml.safe_load(categories_response.content)
categories=categories_data['categories']

weightstable = []
metacattable = []

#iterate over all keys in categories and print them but not Category "JavaOverall"
for metacategory in categories:
    if metacategory in ["C.FalseOverall","C.TrueOverall","Java.Overall","C.Huawei-Concurrency-Challenges","SV-LIB.Overall","C.Overall","C.ValidationCrafted"]:
        continue
    # retrieve the properties of the category
    properties = categories[metacategory].get('properties', [])
    categories_list = categories[metacategory].get('categories', [])
    catcount = 0
    for category in categories_list:
        df_filtered = df[df['category'] == category]
        catcount += len(df_filtered)

    # avg is the average number of tasks per category in this metacategory
    avg=1.0
    if categories_list:
        avg = catcount / len(categories_list)

    for category in categories_list:
        #property, category = category.split(".", 1)
        #df_filtered = df[(df['property'] == property) & (df['category'] == category)]
        df_filtered = df[df['category'] == category]
        count = len(df_filtered)
        weight = "inf" if count == 0 else round(avg / count, 3)
        #print("  Category:", category, "Property:", property," count:", count, " weight:", weight)
        property = category.split(".")[1]
        weightstable.append({'metacategory': metacategory, 'category': category,'property':property, 'taskcount': count, 'weight': weight})

    print(" Total tasks in metacategory", metacategory, ":", catcount)
    metacattable.append({'metacategory': metacategory, 'total_tasks': catcount})

# sum of all total_tasks in metacattable
all_metacat = sum(item['total_tasks'] for item in metacattable)
avg_metacat = all_metacat / len(metacattable)
print("Average tasks per metacategory:", avg_metacat)
for metacategory in metacattable:
    metacategory['metaweight'] = "inf" if metacategory['total_tasks'] == 0 else round(avg_metacat / metacategory['total_tasks'], 3)


weightdf = pd.DataFrame(weightstable)

metacatdf = pd.DataFrame(metacattable)

ovaralldf=pd.merge(weightdf,metacatdf,on=['metacategory'],how='left')
for index, row in ovaralldf.iterrows():
    if row['weight'] == 'inf' or row['metaweight'] == 'inf':
        ovaralldf.at[index, 'overallweight'] = 'inf'
    else:
        ovaralldf.at[index, 'overallweight'] = round(row['weight'] * row['metaweight'], 3)

#weightdf.to_csv("category_weights.csv", index=False)
#print("Wrote category_weights.csv")
#metacatdf.to_csv("metacategory_totals.csv", index=False)
#print("Wrote metacategory_totals.csv")
ovaralldf.to_csv("debug.csv", index=False)


df=pd.merge(df,ovaralldf,on=['category','property'],how='left')


df.to_csv(args.outcsv, index=False)
print(f"Wrote {args.outcsv}")