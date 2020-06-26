type member = {
  rank: int,
  name: string,
  phase: int,
  release: int,
  allTime: int,
};

type entry = array(string);

external parseEntry: Js.Json.t => entry = "%identity";

let safeParseInt = str =>
  try(int_of_string(str)) {
  | Failure(_) => 0
  };

let fetchLeaderboard = () => {
  ReFetch.fetch(
    "https://sheets.googleapis.com/v4/spreadsheets/1Nq_Y76ALzSVJRhSFZZm4pfuGbPkZs2vTtCnVQ1ehujE/values/B4:H?key="
    ++ Next.Config.google_api_key,
    ~method_=Get,
    ~headers={
      "Accept": "application/json",
      "Content-Type": "application/json",
    },
  )
  |> Promise.bind(Bs_fetch.Response.json)
  |> Promise.map(r => {
       let results =
         Option.bind(Js.Json.decodeObject(r), o => Js.Dict.get(o, "values"));

       switch (Option.bind(results, Js.Json.decodeArray)) {
       | Some(resultsArr) =>
         let res =
           Array.map(parseEntry, resultsArr)
           |> Array.map(entry => {
                {
                  rank: safeParseInt(entry[0]),
                  name: entry[2],
                  phase: safeParseInt(entry[3]),
                  release: safeParseInt(entry[6]),
                  allTime: safeParseInt(entry[3]),
                }
              });
         Js.log(res);
         res;
       | None => [||]
       };
     })
  |> Js.Promise.catch(_ => Promise.return([||]));
};

module Styles = {
  open Css;

  let leaderboardContainer =
    style([
      width(`percent(100.)),
      // maxWidth(rem(41.)),
      margin2(~v=`zero, ~h=`auto),
      selector("hr", [margin(`zero)]),
    ]);

  let leaderboard =
    style([
      background(white),
      width(`percent(100.)),
      borderRadius(px(3)),
      paddingTop(`rem(1.)),
      Theme.Typeface.ibmplexsans,
      fontSize(rem(1.5)),
      lineHeight(rem(1.5)),
      color(Theme.Colors.leaderboardMidnight),
      selector(
        "div:nth-child(even)",
        [backgroundColor(`rgba((245, 245, 245, 1.)))],
      ),
    ]);

  let leaderboardRow =
    style([
      padding2(~v=`rem(1.), ~h=`rem(1.)),
      display(`grid),
      gridColumnGap(rem(1.5)),
      gridTemplateColumns([
        rem(1.),
        rem(5.5),
        rem(5.5),
        rem(3.5),
        rem(3.5),
      ]),
      media(
        Theme.MediaQuery.notMobile,
        [
          width(`percent(100.)),
          gridTemplateColumns([
            rem(3.5),
            `auto,
            rem(9.),
            rem(8.),
            rem(8.),
          ]),
        ],
      ),
    ]);

  let headerRow =
    merge([
      leaderboardRow,
      style([
        paddingBottom(`rem(0.5)),
        fontSize(`rem(1.)),
        fontWeight(`semiBold),
        textTransform(`uppercase),
        letterSpacing(`rem(0.125)),
      ]),
    ]);

  let cell = style([whiteSpace(`nowrap), overflow(`hidden)]);
  let flexEnd = style([justifySelf(`flexEnd)]);
  let rank = merge([cell, flexEnd]);
  let username =
    merge([cell, style([textOverflow(`ellipsis), fontWeight(`semiBold)])]);
  let pointsCell = merge([cell, style([justifySelf(`flexEnd)])]);
  let activePointsCell =
    merge([cell, style([justifySelf(`flexEnd), fontWeight(`semiBold)])]);
  let inactivePointsCell = merge([pointsCell, style([opacity(0.5)])]);

  let loading =
    style([
      padding(`rem(5.)),
      color(Theme.Colors.leaderboardMidnight),
      textAlign(`center),
    ]);
};

module LeaderboardRow = {
  [@react.component]
  let make = (~rank, ~member) => {
    <>
      <div className=Styles.leaderboardRow>
        <span className=Styles.rank>
          {React.string(string_of_int(rank))}
        </span>
        <span className=Styles.username> {React.string(member.name)} </span>
        <span className=Styles.activePointsCell>
          {React.string(string_of_int(member.release))}
        </span>
        <span className=Styles.inactivePointsCell>
          {React.string(string_of_int(member.phase))}
        </span>
        <span className=Styles.inactivePointsCell>
          {React.string(string_of_int(member.allTime))}
        </span>
      </div>
    </>;
  };
};

type filter =
  | All
  | Genesis
  | NonGenesis;

type sort =
  | Release
  | Phase
  | AllTime;

type state = {
  loading: bool,
  members: array(member),
};
let initialState = {loading: true, members: [||]};

type actions =
  | UpdateMembers(array(member));

let reducer = (_, action) => {
  switch (action) {
  | UpdateMembers(members) => {loading: false, members}
  };
};

[@react.component]
let make = () => {
  let (state, dispatch) = React.useReducer(reducer, initialState);

  React.useEffect0(() => {
    fetchLeaderboard() |> Promise.iter(e => dispatch(UpdateMembers(e)));
    None;
  });

  <div className=Styles.leaderboardContainer>
    <div id="testnet-leaderboard" className=Styles.leaderboard>
      <div className=Styles.headerRow>
        <span className=Styles.flexEnd> {React.string("Rank")} </span>
        <span> {React.string("Name")} </span>
        <span className=Styles.flexEnd> {React.string("This Release")} </span>
        <span className=Styles.flexEnd> {React.string("This Phase")} </span>
        <span className=Styles.flexEnd> {React.string("All Time")} </span>
      </div>
      <hr />
      {Array.map(
         member =>
           <LeaderboardRow
             key={string_of_int(member.rank)}
             rank={member.rank}
             member
           />,
         state.members,
       )
       |> React.array}
      {state.loading
         ? <div className=Styles.loading> {React.string("Loading...")} </div>
         : React.null}
    </div>
  </div>;
};
