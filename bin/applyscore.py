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
data_levels = data_true["level"].groupby(data["level"]).count().rename("verdicts")
data_cumlevels = data_levels.cumsum().rename("verdicts_accu")
data_levels_pct = (data_levels / data_levels.sum() * 100).rename("percent")
tmp=pd.concat([data_cumlevels, data_levels, data_levels_pct], axis=1)
print(tmp)
tmp.to_markdown(args.totalscore.replace(".csv",".confirmedtrue.md"))


print()

def is_ro(s):
    return s.startswith("TIMEOUT") or s.startswith("OUT OF MEMORY")

print("out of resources (TIMEOUT, OUT OF MEMORY):")
data_ro = data[data["verdict"].map(is_ro)]

# breaking resource out verdicts down by levels, if there are any
data_ro_levels = data_ro["levelstarted"].groupby(data["levelstarted"]).count().rename("maxresource")
data_ro_cumlevels = data_ro_levels.cumsum().rename("maxresource_accu")
data_ro_levels_pct = (data_ro_levels / data_ro_levels.sum() * 100).rename("percent")
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
data_weights_cumlevels = data_weights_levels.cumsum().rename("score_accu").round().astype(int)
data_weights_levels = data_weights_cumlevels.diff().fillna(data_weights_cumlevels).astype(int).rename("score_overall")
data_weights_levels_pct = (data_weights_levels / data_weights_levels.sum() * 100).rename("percent")
print(pd.concat([data_weights_cumlevels, data_weights_levels, data_weights_levels_pct], axis=1))
tmp=pd.concat([data_weights_cumlevels, data_weights_levels, data_weights_levels_pct], axis=1)
tmp.to_csv(args.totalscore, index_label="level")
tmp.to_markdown(args.totalscore.replace(".csv",".md"))

# print(data_weights_true)
data_weights_meta = data_weights_true[data_weights_true["result"] == "correct"].groupby(data_weights_true["metacategory"])["weight"].sum().round().astype(int)*2 #assuming only trues
verdicts_meta = data_weights_true[data_weights_true["result"] == "correct"].groupby(data_weights_true["metacategory"])["weight"].count().rename("verdicts")
print(pd.concat([verdicts_meta,data_weights_meta],axis=1))
data_weights_meta.to_csv(args.outpercat, header=["metacategory_score"])
data_weights_meta.to_markdown(args.outpercat.replace(".csv",".md"))
