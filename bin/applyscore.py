# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "pandas==3.0.0rc0" # this version tells why merge validation fails
# ]
# ///

import argparse
import pandas as pd


parser = argparse.ArgumentParser()
parser.add_argument("--tablecsv", default="results/current/nightly.table.csv", help="Path to the table CSV file")
parser.add_argument("--weightscsv", default="results/current/weights.csv", help="Path to the weights CSV file")
parser.add_argument("--outcsv", default="results/current/finalscores.csv", help="Path to output CSV file")
parser.add_argument("--outpercat", default="results/current/scorespercat.csv", help="Path to output category scores CSV file")
parser.add_argument("--totalscore", default="results/current/totalscore.csv", help="Path to output total score CSV file")
args = parser.parse_args()

data = pd.read_csv(args.tablecsv,header="infer", sep="\t")

# fillna levels with 0
data["level"] = data["level"].fillna(0).astype(int)
data["levelstarted"] = data["levelstarted"].fillna(0).astype(int)

print("confirmed true:")
data_true = data[(data["verdict"] == "true") & (data["result"] == "correct")]


# breaking true verdicts down by levels, if there are any
data_levels = data_true["level"].groupby(data["level"]).count().rename("Verdicts")
data_cumlevels = data_levels.cumsum().rename("Verdicts accum.")
data_levels_pct = (data_levels / data_levels.sum() * 100).rename("Contrib").round(2).astype(str)+" %"
tmp=pd.concat([data_cumlevels, data_levels, data_levels_pct], axis=1)
print(tmp)
tmp.to_markdown(args.totalscore.replace(".csv",".confirmedtrue.md"))


print()

def is_ro(s):
    return s.startswith("TIMEOUT") or s.startswith("OUT OF MEMORY")

print("out of resources (TIMEOUT, OUT OF MEMORY):")
data_ro = data[data["verdict"].map(is_ro)]

# breaking resource out verdicts down by levels, if there are any
data_ro_levels = data_ro["levelstarted"].groupby(data["levelstarted"]).count().rename("Exceeded Resources")
data_ro_cumlevels = data_ro_levels.cumsum().rename("Exceeded Resources accum.")
data_ro_levels_pct = (data_ro_levels / data_ro_levels.sum() * 100).rename("Contrib").round(2).astype(str)+" %"
tmp=pd.concat([data_ro_cumlevels, data_ro_levels, data_ro_levels_pct], axis=1)
print(tmp)
tmp.to_markdown(args.totalscore.replace(".csv",".outofresources.md"))

print("Overall score:")
data_score = data #[data["status"] == "true"]
# print(data_score)
weights = pd.read_csv(args.weightscsv,header="infer")
weights = weights[weights["overallweight"].notnull()]
# remove column "expected" from weights
weights = weights.drop(columns=["expected"])
# print(weights)
data_weights = pd.merge(data_score, weights, how="left", left_on=["ymlfile", "property"], right_on=["ymlfile", "property"], validate="1:1")

data_weights.to_csv(args.outcsv, index=False)

data_weights_true = data_weights[(data_weights["verdict"] == "true") & (data_weights["result"] == "correct")]
#print(data_weights_true)

# breaking score contribution to total score down by levels within each metacategory
data_weights_levels = data_weights_true.groupby(data_weights_true["level"])["overallweight"].sum()*2 # assuming only trues
data_weights_cumlevels = data_weights_levels.cumsum().rename("Score accum.").round().astype(int)
data_weights_levels = data_weights_cumlevels.diff().fillna(data_weights_cumlevels).astype(int).rename("Score")
data_weights_levels_pct = (data_weights_levels / data_weights_levels.sum() * 100).rename("Contrib").round(2).astype(str)+" %"
print(pd.concat([data_weights_cumlevels, data_weights_levels, data_weights_levels_pct], axis=1))
tmp=pd.concat([data_weights_cumlevels, data_weights_levels, data_weights_levels_pct], axis=1)
tmp.to_csv(args.totalscore, index_label="level")
tmp.to_markdown(args.totalscore.replace(".csv",".md"))

# print(data_weights_true)
data_weights_meta = data_weights_true[data_weights_true["result"] == "correct"].groupby(data_weights_true["metacategory"])["weight"].sum().round().astype(int).rename("Score")*2 #assuming only trues
verdicts_meta = data_weights_true[data_weights_true["result"] == "correct"].groupby(data_weights_true["metacategory"])["weight"].count().rename("Verdicts")
wrong_meta = data_weights[data_weights["result"] == "wrong"].groupby(data_weights["metacategory"])["weight"].count()
cputime_meta = (data_weights.groupby(data_weights["metacategory"])["cputime"].sum().rename("CPU time")/60).round().astype(int).astype(str)+" min"
wrong_meta = wrong_meta.reindex(verdicts_meta.index).fillna(0).astype(int).rename("Wrong")
tmp=pd.concat([verdicts_meta,wrong_meta,data_weights_meta,cputime_meta],axis=1)
print(tmp)
tmp.to_csv(args.outpercat)
tmp.to_markdown(args.outpercat.replace(".csv",".md"))
