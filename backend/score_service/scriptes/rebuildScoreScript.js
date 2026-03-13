require("dotenv").config();

const mongoose = require("mongoose");

const TrustScore = require("../models/TrustScore");
const { rebuildGlobalScoreForStaff } = require("../services/scoreAggregator");

async function run() {
  await mongoose.connect(process.env.MONGO_URI);

  console.log("Mongo connected");

  const staffIds = await TrustScore.distinct("staffId");

  console.log("staff count:", staffIds.length);

  let done = 0;

  for (const staffId of staffIds) {
    await rebuildGlobalScoreForStaff(staffId);
    done++;

    if (done % 50 === 0) {
      console.log("processed:", done);
    }
  }

  console.log("rebuild completed:", done);

  process.exit();
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});