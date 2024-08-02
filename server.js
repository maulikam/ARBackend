const express = require('express');
const path = require('path');
const bodyParser = require('body-parser');
const fs = require('fs');
const app = express();
const port = 3000;

app.use(express.static(path.join(__dirname, 'public')));
app.use(bodyParser.json({ limit: '50mb' }));

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.post('/save-data', (req, res) => {
  const data = req.body;
  const filePath = path.join(__dirname, 'data', `${Date.now()}.json`);
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
  res.sendStatus(200);
});

app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
});
