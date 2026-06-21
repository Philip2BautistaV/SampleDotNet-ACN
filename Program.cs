var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "1t Test for Today");

app.Run();
